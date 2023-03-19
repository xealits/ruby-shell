#!/usr/bin/ruby
##
# a shell

require 'open3'
require 'irb'
require 'readline'

#class Console
#
#  def run

$x = 55
x = 5

# somehow, is I just use binding inside the console method
# the local variable x shows up empty in: echo #{x}
# stdin> echo ${x}
# 
#   0
# stdin> irb
# with the global binding passed as at_binding
# x is accessible

def console (at_binding = nil)
  #x = 7

  while usr_command = Readline.readline('stdin> ', true)
  #while true
    #prompt = 'stdin> '
    #print prompt
    #usr_command = gets

    # special control cases
    if usr_command.strip.empty?
      next
    elsif usr_command.strip[...4] == 'exit'
      #at_binding.eval usr_command
      #exit
      return usr_command.strip[4...].to_i

    elsif usr_command.strip[..2] == 'irb'
      #return # get out to the main irb
      #IRB.start
      at_binding.irb
      #binding.irb

      #IRB.setup nil
      #IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
      ##IRB.conf[:MAIN_CONTEXT] = IRB.CurrentContext
      #require 'irb/ext/multi-irb'
      #IRB.irb nil, self

      #IRB.irb Console
      #irb Console
      next
    end

    # normal shell command
    #puts "usr_command: #{usr_command}"
    if at_binding
      usr_command = at_binding.eval('"' + usr_command + '"')
    else
      usr_command = eval('"' + usr_command + '"')
    end
    #usr_command = binding.eval('"' + usr_command + '"')
    #puts "usr_command: #{usr_command}"

    stdin, stdout, stderr, wait_thr = Open3.popen3(usr_command)

    puts "#{stdout.read} #{stderr.read} #{wait_thr.value.exitstatus}"
  end
end

#  end
#  #module_function :run
#
#end
#
#c = Console.new
#c.run

# launch irb, which launches the console function
# so that you can `return` from the console and get to the main irb
#require 'irb'

#IRB.setup nil
#IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
##IRB.conf[:MAIN_CONTEXT] = IRB.CurrentContext
##IRB.conf[:MAIN_CONTEXT] = IRB::Irb.context
#require 'irb/ext/multi-irb'
##IRB.irb nil, self
#IRB.irb nil, console

#binding.irb # false # no show_code argument in ruby 3.0

exit_code = console binding
#exit_code = console
#exit exit_code
Kernel.exit exit_code
