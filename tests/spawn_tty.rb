#!/usr/bin/ruby

pid = Process.spawn('cat', :in => STDIN, :out =>STDOUT)
Process.wait(pid)
