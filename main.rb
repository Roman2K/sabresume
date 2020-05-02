require 'utils'

conf = Utils::Conf.new("config.yml")
log = Utils::Log.new level: :info
log.level = :debug if ENV["DEBUG"] == "1"
sab = Utils::SABnzbd.new conf[:sab], log: log

if sab.queue.inject(Set.new) { |s,i| s << i.fetch("status") }.to_a == ["Queued"]
  log.warn "all paused, resuming"
  sab.queue_resume
end
