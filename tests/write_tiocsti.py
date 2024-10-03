# https://stackoverflow.com/questions/29614264/unable-to-fake-terminal-input-with-termios-tiocsti/29616465#29616465 

import fcntl
import sys
import termios

stdin_fd = sys.argv[1]
with open(stdin_fd, 'w') as fd:
    for c in "ls\n":
        fcntl.ioctl(fd, termios.TIOCSTI, c)
