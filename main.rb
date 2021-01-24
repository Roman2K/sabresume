require 'utils'
require 'redis'

conf = Utils::Conf.new("config.yml")
log = Utils::Log.new level: :info
log.level = :debug if ENV["DEBUG"] == "1"
sab = Utils::SABnzbd.new conf[:sab], log: log
redis = Redis.new url: conf[:redis]

class DryRunSAB < BasicObject
  def initialize(sab, log:)
    @sab = sab
    @log = log
  end

  private def method_missing(m,*a,&b)
    case m
    when :history, :queue
      @sab.public_send m,*a,&b
    else
      @log.info "sab.#{m}(#{o = a.shift and "#{o.inspect}, "}#{a.size} args...)"
    end
  end
end
if conf[:dry_run]
  log.info "dry run"
  sab = DryRunSAB.new sab, log: log["dry run"]
else
  log.info "real mode"
end

stats = sab.queue.group_by { _1.fetch "status" }
pp stats: stats.transform_values(&:size)
item_log = -> item { log[filename: item.fetch("filename")] }

class FailureManager
  def initialize(sab, redis)
    @sab = sab
    @redis = redis
  end

  def add_stuck(item, log:)
    nzo_id = item.fetch "nzo_id"
    key = "sabresume:strategies:#{nzo_id}"
    if @redis.sadd(key, "restart")
      @redis.expire key, 3600
      log.info "restarting"
      @sab.restart
    elsif @redis.sadd(key, "delete")
      log.info "deleting"
      @sab.queue_del nzo_id, del_files: true
      @redis.del key
    else
      log.error "already tried all strategies"
    end
  end
end

failmgr = FailureManager.new sab, redis
stats.fetch("Downloading", []).each do |item|
  next unless item.fetch("eta") == "unknown"
  get_f = -> k { item.fetch(k).to_f }
  next unless get_f["percentage"] > 0 || get_f["mbleft"] > get_f["mb"]
  ilog = item_log.(item)
  ilog.warn "download stuck"
  failmgr.add_stuck item, log: ilog
  exit 0
end

stats.fetch("Paused", []).each do |item|
  item_log.(item).warn "resuming download"
  sab.queue_resume item.fetch("nzo_id")
end

if stats.keys - %w[Paused Fetching] == ["Queued"]
  log.warn "all queued, resuming"
  sab.queue_resume_all
end
