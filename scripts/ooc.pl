#!/usr/bin/env perl
# -*- coding: utf-8 -*-
# ----------------------------------------------------------------------------
# Copyright (C) 2014 André Erdmann <dywi@mailerd.de>
# Distributed under the terms of the GNU General Public License;
# either version 2 of the License, or (at your option) any later version.
# ----------------------------------------------------------------------------
#
# Script for running only one instance of a command at a time.
# Useful for processing udev events, writing cron jobs, ...
#
# Synchronization is realized by locking a pidfile which records the process
# id of the most recent script (that is/was running the command).
#
# ----------------------------------------------------------------------------
#
# Usage:
# <script> {-h|-D|-N|-b|-i|-T <seconds>|-t <seconds>|-p <file>} <pidfile> [--] <command> [arg...]
#
# The --block(-b)/--no-block(-i) switches can be used to control whether the
# script should exit if another instance is already running (non-blocking)
# or wait until it finishes (blocking). non-blocking mode is the default.
#
# --settle-before (-T) sets the time to sleep *before* trying to acquire the
# lock, which gives other instances the chance to get the lock.
# Multiple -T options accumulate, so specifying a base value of "-T 3" and
# substracting an attr-based value "-T -<attr>" in udev rules can be
# used to prioritize events with a higher <attr> value (in non-blocking mode).
# An effective sleep time <= 0 is interpreted as "no --settle-before".
#
# --settle-after (-t) sets the time to sleep *after* getting the lock.
# This can be used to let things settle (and block other instances).
# -t options accumulate as well, with the same objections as for -T.
#
# --settle-{success,fail} (-X/-x) set the time to sleep *after* the command
# returned with an exit code indicating success/failure.
#
# Specifying "--" or "" as pidfile disables locking (see $usage).
#
# By default, this script forks to background before sleeping / locking /
# running the command. Use --no-fork (-N) to disable this behavior.
#
#
# Note:
#   <min_sleep_time> := sum ( max(0,<settle_$type>) )
#    and not sum(<settle_$type>)
#
# TODO:
# * signal handling (using sigtrap)
# * blocking mode could be racy...
#
# ----------------------------------------------------------------------------

package ooc;

use strict;
use warnings;
use Fcntl            qw(:DEFAULT :flock :seek :mode);
use File::Basename   qw(basename dirname);
use POSIX            qw(setsid :sys_wait_h);
use Cwd              qw(chdir);
use sigtrap          qw(die normal-signals);

our $VERSION     = "0.1";
our $NAME        = "ooc";
our $DESCRIPTION = "run exactly one instance of a command at any time";


my $prog_name   = basename($0);
my $short_usage =
"$prog_name {-[hVqDNbi]|-[TtXx] <s>|-[p12] <f>} <pidfile> [--] <command> [arg...]"
;

my $usage = "$NAME ($VERSION) - $DESCRIPTION

Usage:
  $short_usage

Options:
  -h, --help                       show this message and exit
  -V, --version                    print the version and exit
  -q, --quiet                      suppress most error messages [False]
  -D, --daemonize                  daemonize [True]
  -N, --no-fork                    don\'t daemonize [False]
  -b, --block                      enable blocking mode [False]
                                    (wait for lock)
  -i, --no-block                   enable non-blocking mode [True]
                                    (lock or exit immediately)
  -T, --settle-before  <seconds>   sleep <seconds> before locking [0]
  -t, --settle-after   <seconds>   sleep <seconds> after  locking [0]
                                    (before running <command>)
  -X, --settle-success <seconds>   sleep <seconds> if <command> succeeded [0]
  -x, --settle-fail    <seconds>   sleep <seconds> if <command> failed [0]
  -p, --cmd-pidfile    <file>      write the command\'s pid to <file> [False]
  -1, --stdout         <file>      redirect stdout to <file> [False]
  -2, --stderr         <file>      redirect stderr to <file> [False]

Passing \"--\" or \"\" as <pidfile> disables locking.
Multiple --settle options accumulate (\"-t 3 -t -2\" is the same as \"-t 1\").
";

my $LOCKFILE;
my $LOCKFILE_FH;

# void release_global_lock ( *args_ignored )
#
sub release_global_lock {
   if ( $LOCKFILE && defined $LOCKFILE_FH ) {
      &unlock_pidfile ( $LOCKFILE, $LOCKFILE_FH );
      $LOCKFILE_FH = undef;
   }
}

# void acquire_as_global_lock ( $lockfile, $lockfile_fh, $flock_flags )
#
sub acquire_as_global_lock {
   $LOCKFILE       = shift;
   my $lockfile_fh = shift;
   my $flock_flags = shift;

   # lock / write pid
   &lock_pidfile ( $LOCKFILE, $lockfile_fh, $flock_flags );

   $LOCKFILE_FH = $lockfile_fh;
}


# int is_opt ( \@argv, options... )
#
#  Returns 1 if argv[0] is in options, else 0.
#
sub is_opt {
   my $key = shift->[0];
   foreach(@_) { return 1 if ( $_ eq $key ); };
   return 0;
}

# void autoflush_fh ( $fh )
#
sub autoflush_fh {
   my $bak = select($_[0]); $| = 1; select($bak);
}

# int dodir ( $dirpath, $mode, [$parent_mode:=0775] )
#
#  Recursively creates the given directory.
#
#  Returns 0 if $dirpath could not be created, else non-zero.
#
sub dodir {
   my $dirpath     = shift;
   my $mode        = shift;
   my $parent_mode = @_ ? shift : S_IRWXU|S_IRWXG|S_IXOTH|S_IROTH;
   my $parent_dir  = undef;

   return 1 if ( ( ! $dirpath ) || ( -d $dirpath ) );

   $parent_dir = dirname($dirpath);
   if ( $parent_dir ne $dirpath ) {
      # resolve by recursion
      return 0 unless &dodir ( $parent_dir, $parent_mode, $parent_mode );
   }

   return 2 if mkdir ( $dirpath, $mode );
   return 3 if ( -d $dirpath );

   return 0;
}

# void unlock_pidfile ( $file_path, $file_handle ), raises die()
#
#  Unlocks and closes the pidfile.
#
sub unlock_pidfile {
   my ( $f, $fh ) = @_;

   flock ( $fh, LOCK_UN ) or die "failed to unlock pidfile $f: $!";
   close ( $fh ) or die "failed to close pidfile $f: $!";
}

# void lock_pidfile ( $file_path, $file_handle, $flock_flags ), raises die()
#
#  Locks an already opened file and writes the process id to it.
#
sub lock_pidfile {
   my ( $f, $fh, $flock_flags ) = @_;

   flock ( $fh, $flock_flags ) or die "failed to lock pidfile $f: $!";

   # turn off buffering
   &autoflush_fh($fh);

   # make sure that no one appended to text to the pidfile
   if ( ! seek ( $fh, 0, SEEK_END  ) ) {
      my $err = $!;
      &unlock_pidfile ( $f, $fh );
      die "failed to seek pidfile $f: $err";
   }

   # empty the file
   if ( ! truncate ( $fh, 0 ) ) {
      my $err = $!;
      &unlock_pidfile ( $f, $fh );
      die "failed to truncate pidfile $f: $err";
   }

   # seek to 0
   if ( ! seek ( $fh, 0, SEEK_SET  ) ) {
      my $err = $!;
      &unlock_pidfile ( $f, $fh );
      die "failed to seek pidfile $f: $err";
   }

   # write pid to file
   if ( ! print $fh $$ ) {
      my $err = $!;
      &unlock_pidfile ( $f, $fh );
      die "failed to write pidfile $f: $err";
   }
}

# int system_write_pidfile ( $pidfile, \@argv )
#
#  Provides functionality similar to system(), but writes the command's
#  process id to a file (and empties the file when the command is done).
#
sub system_write_pidfile {
   my $pidfile = $_[0];
   my @argv    = @{$_[1]};
   my $fh      = undef;
   my $pid     = fork();
   my $ret     = -1;

   if ( $pid == 0 ) {
      # child process: exec argv

      # don't get trapped (just to be sure)
      $LOCKFILE_FH = undef;

      exec { $argv[0] } @argv;
      die;

   } elsif ( $pid ) {
      # parent process
      #  write pidfile (if any), wait for child, truncate pidfile

      # write pid
      if ( $pidfile ) {
         if ( open ( $fh, '>', $pidfile ) ) {
            &autoflush_fh($fh);
            print $fh $pid;
            # keep $fh open
         } else {
            warn "failed to write command pidfile $pidfile: $!";
         }
      }

      # wait
      waitpid ( $pid, 0 );
      $ret = $?;

      # truncate pidfile
      if ( $fh ) {
         truncate ( $fh, 0 )
            or warn "failed to truncate command pidfile $pidfile: $!";
         close ( $fh )
            or warn "failed to close command pidfile $pidfile: $!";
      }

   } else {
      # parent process, fork failed
      warn "cannot run command: failed to fork ($!)";
   }

   return $ret;
}

# void _handle_str_option ( \@argv, $option_var, $value_var ), raises die()
#
sub _handle_str_option {
   $_[1] = shift(@{$_[0]});
   @{$_[0]} or die "option " . $_[1] . " needs an arg.";
   $_[2] = shift(@{$_[0]});
}

# void handle_str_option ( \@argv, $dest_var ), raises die()
#
sub handle_str_option {
   my $option;
   &_handle_str_option ( $_[0], $option, $_[1] );
}

# void handle_int_option ( \@argv, $dest_var ), raises die()
#
sub handle_int_option {
   my $option;
   my $str_value;
   my $value;

   &_handle_str_option ( $_[0], $option, $str_value );
   $_[1] = int($str_value);

   ( $_[1] || $_[1] == 0 )
      or die "invalid value for ${option} arg: \'${str_value}\'";
}

# void handle_settle_option ( \@argv, $dest_var ), raises die()
#
sub handle_settle_option {
   my $value;
   &handle_int_option ( $_[0], $value );
   $_[1] += $value;
}

# int main ( \@argv ), raises die()
#
sub main {
   my @argv           = @{$_[0]};
   my $settle_before  = 0;
   my $settle_after   = 0;
   my $settle_success = 0;
   my $settle_fail    = 0;
   my $pidfile        = undef;
   my $pidfile_fh     = undef;
   my $retcode        = 0;
   my $flock_flags    = LOCK_EX|LOCK_NB;
   my $daemonize      = 1;
   my $daemon_pid     = undef;
   my $cmd_pidfile    = undef;

   # _partially_ parse args until pidfile is set
   #   given($arg) { when($option) ... } ...
   #
   while ( ! defined ( $pidfile ) ) {
      @argv or die "Usage: $short_usage\n\nmissing <pidfile> or \"--\" arg";

      if ( &is_opt ( \@argv, "--daemonize", "-D" ) ) {
         shift(@argv);
         $daemonize = 1;

      } elsif ( &is_opt ( \@argv, "--no-fork", "-N" ) ) {
         shift(@argv);
         $daemonize = 0;

      } elsif ( &is_opt ( \@argv, "--no-block", "-i" ) ) {
         shift(@argv);
         $flock_flags |= LOCK_NB;

      } elsif ( &is_opt ( \@argv, "--block", "-b" ) ) {
         shift(@argv);
         $flock_flags &= ~LOCK_NB;

      } elsif ( &is_opt ( \@argv, "--settle-before", "-T" ) ) {
         &handle_settle_option ( \@argv, $settle_before );

      } elsif ( &is_opt ( \@argv, "--settle-after", "-t" ) ) {
         &handle_settle_option ( \@argv, $settle_after );

      } elsif ( &is_opt ( \@argv, "--settle-success", "-X" ) ) {
         &handle_settle_option ( \@argv, $settle_success );

      } elsif ( &is_opt ( \@argv, "--settle-fail", "-x" ) ) {
         &handle_settle_option ( \@argv, $settle_fail );

      } elsif ( &is_opt ( \@argv, "--cmd-pidfile", "-p" ) ) {
         &handle_str_option ( \@argv, $cmd_pidfile );

      } elsif ( &is_opt ( \@argv, "--help", "-h" ) ) {
         print $usage;
         return 0;

      } elsif ( &is_opt ( \@argv, "--version", "-V" ) ) {
         print $VERSION . "\n";
         return 0;

      } else {
         # <pidfile> or "--"
         $pidfile = shift(@argv);
         $pidfile = "" if ( $pidfile eq "--" );
         # last not necessary
         last;
      }
   }

   # parse "--" arg
   shift(@argv) if ( @argv && $argv[0] eq "--" );

   # check if there's a command to be run
   @argv or die "Usage: $short_usage\n\nno command specified";

   # create $pidfile, $cmd_pidfile dirs
   foreach ($pidfile, $cmd_pidfile) {
      if ($_) {
         &dodir ( dirname($_), S_IRWXU|S_IXGRP|S_IRGRP )
            or die "failed to create directory $_.";
      }
   }

   # daemonize?
   if ( $daemonize ) {
      $daemon_pid = fork();
      exit(0) if $daemon_pid;
      defined ( $daemon_pid ) or die "failed to fork: $!";

      umask ( S_IWGRP|S_IWOTH );
      setsid()   or die "setsid failed: $!";
      chdir("/") or die "chdir / failed: $!";
      # COULDFIX: close stdin/out/err
   }

   # let things settle (pre-lock)
   sleep ( $settle_before ) if ( $settle_before > 0 );

   # lock pidfile
   if ( $pidfile ) {
      # open
      sysopen ( $pidfile_fh, $pidfile, O_CREAT|O_RDWR, S_IRUSR|S_IWUSR|S_IRGRP )
         or die "failed to open pidfile $pidfile: $!";

      # lock / write pid // set global LOCKFILE{,_FH}
      &acquire_as_global_lock ( $pidfile, $pidfile_fh, $flock_flags );
   }

   # let things settle (post-lock)
   sleep ( $settle_after ) if ( $settle_after > 0 );

   # run command, get retcode
   $retcode = system_write_pidfile ( $cmd_pidfile, \@argv ) >> 8;

   # let things settle (post-exec)
   if ( $retcode < 0 ) {
      # failed to fork, don't waste time!
   } elsif ( $retcode ) {
      sleep ( $settle_fail ) if ( $settle_fail > 0 );
   } else {
      sleep ( $settle_success ) if ( $settle_success > 0 );
   }

   # unlock pidfile
   if ( $pidfile && $pidfile_fh != $LOCKFILE_FH ) {
      # some other function has claimed the global lock, just release "my" lock
      &unlock_pidfile ( $pidfile, $pidfile_fh ) if ($pidfile);
   } else {
      # release the global lock
      &release_global_lock();
   }

   return $retcode < 0 ? 254 : $retcode;
}

# ~if __name__ == '__main__'
unless (caller) {
   exit(main(\@ARGV));
}

END {
   &release_global_lock();
}
