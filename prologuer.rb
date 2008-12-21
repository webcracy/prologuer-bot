#To start (run in the background): ruby prologuer.rb start
#To restart: ruby prologuer.rb restart
#To stop: ruby prologuer.rb stop
#To run in the foreground: ruby prologuer.rb run

require 'rubygems'
require 'daemons'

def whatstheenv?(envi)
  if envi != nil
    return envi
  elsif envi == nil
    return 'config'
  end
end

ENV_SET = whatstheenv?(ARGV[1])

if ARGV[0].to_s == 'start' or ARGV[0].to_s == 'run'
  puts "___ Bot running in #{ENV_SET} environnement..."
  puts "___ You can edit prologuer.rb to use other configs"
  puts "___ Type 'ruby prologuer.rb stop' to disconnect the bot"
elsif ARGV[0].to_s == 'restart'
  puts "___ Bot restarted in #{ENV_SET} environnement..."
  puts "___ Type 'ruby prologuer.rb stop' to disconnect the bot"
else
  puts "___ Bot disconnected."
end

Daemons.run('lib/prologuer_lib.rb')