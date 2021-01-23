require 'utils'
require 'redis'

conf = Utils::Conf.new("config.yml")
log = Utils::Log.new level: :info
log.level = :debug if ENV["DEBUG"] == "1"
sab = Utils::SABnzbd.new conf[:sab], log: log
redis = Redis.new url: conf[:redis]

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
  pp item: item if item.fetch("filename") =~ /Insurg.*SPAR/
  if item.fetch("percentage").to_i > 0 && item.fetch("eta") == "unknown"
    ilog = item_log.(item)
    ilog.warn "download stuck"
    failmgr.add_stuck item, log: ilog
    exit 0
  end
end

stats.fetch("Paused", []).each do |item|
  item_log.(item).warn "resuming download"
  sab.queue_resume item.fetch("nzo_id")
end

if stats.keys - %w[Paused Fetching] == ["Queued"]
  log.warn "all queued, resuming"
  sab.queue_resume_all
end
