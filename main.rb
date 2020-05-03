require 'utils'

conf = Utils::Conf.new("config.yml")
log = Utils::Log.new level: :info
log.level = :debug if ENV["DEBUG"] == "1"
sab = Utils::SABnzbd.new conf[:sab], log: log

stats = sab.queue.group_by { |i| i.fetch "status" }
pp stats: stats.transform_values(&:size)

stats.delete("Paused") { [] }.each do |item|
  log[filename: item.fetch("filename")].warn "resuming download"
  sab.queue_resume item.fetch("nzo_id")
end

if stats.keys == ["Queued"]
  log.warn "all queued, resuming"
  sab.queue_resume_all
end
