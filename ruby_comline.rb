#!/usr/bin/ruby
##
# a shell

require 'open3'
require 'irb'
require 'readline'

$x = 55
x = 5

def console (at_binding = nil)
  while usr_command = Readline.readline('stdin> ', true)

    # special control cases
    if usr_command.strip.empty?
      next
    elsif usr_command.strip[...4] == 'exit'
      return usr_command.strip[4...].to_i

    elsif usr_command.strip[...3] == 'irb'
      at_binding.irb
      next

    elsif usr_command.strip[...2] == 'cd' # turn it into z?
      Dir.chdir usr_command.strip[2...].strip
      next
    end

    # exec a system process
    if at_binding
      usr_command = at_binding.eval('"' + usr_command + '"')
    else
      usr_command = eval('"' + usr_command + '"')
    end

    begin
      stdin, stdout, stderr, wait_thr = Open3.popen3(usr_command)
      puts "#{stdout.read} #{stderr.read} #{wait_thr.value.exitstatus}"

    rescue Errno::ENOENT => error
      # command not found
      #puts "command not found: #{usr_command}"
      puts error.message
    end
  end
end

exit_code = console binding
Kernel.exit exit_code
