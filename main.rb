require 'utils'

conf = Utils::Conf.new("config.yml")
log = Utils::Log.new level: :info
log.level = :debug if ENV["DEBUG"] == "1"
sab = Utils::SABnzbd.new conf[:sab], log: log

stats = sab.queue.group_by { _1.fetch "status" }
pp stats: stats.transform_values(&:size)
item_log = -> item { log[filename: item.fetch("filename")] }

stats.fetch("Downloading", []).each do |item|
  item.fetch("percentage").to_i > 0 && item.fetch("eta") == "unknown" or next
  item_log.(item).warn "download stuck, pausing and resuming"
  nzo_id = item.fetch "nzo_id"
  sab.queue_pause nzo_id
  sab.queue_resume nzo_id
end

stats.fetch("Paused", []).each do |item|
  item_log.(item).warn "resuming download"
  sab.queue_resume item.fetch("nzo_id")
end

if stats.keys - %w[Paused Fetching] == ["Queued"]
  log.warn "all queued, resuming"
  sab.queue_resume_all
end
