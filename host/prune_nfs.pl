#!/usr/bin/env perl
#########################
# This scripts deletes files inside of the target directory 
# based on the rules provided inside
# of the configuration file. (prune.yml)
#
# Following the diagram/legend below, 
# the root keys of YAML configuration file
# are interpreted as directories 
# where its children are regular expressions. 
#
# The listed regular expressions are used to
# determine which files to delete.
# 
# using `/` as the directory selector 
# will apply it across all files/directories
#########LEGEND##########
# path/to/directory:
#   - \.log$       # (text.log)
#   - \.delete_me$ # (foo.delete_me)
#########################
use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use Data::Dumper;
use File::Find;
use File::stat;
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(GetOptions);
Getopt::Long::Configure qw(gnu_getopt);

use YAML qw(LoadFile DumpFile);

my $CHANGE_LOG_TEMPLATE = "Hello! Some changes have have occured in the children directories.
 Below will be a list of modified files. Please note archived files will be removed next rotation period.\n\n";

my $USAGE = "Usage: -d /srv/nfs -c /usr/local/etc/prune_nfs/prune.yml 
  OPTS:
    --help -h               bring up this menu
    --verbose -v            print work

    --dir -d  [dir]         prune directory
    --conf -c [conf.yml]    configuration file - see prune.yml
    --exclude -x [list.txt] exclude directories.
    --archive -a [dir]      archive instead of deleting
              [--copy]      will copy the
                            files instead of moving it.
  LOG:
    --log -l [file.log]     globally log actions
    --change-log            log changes inside of anchors
    
  FILTERS:
    --mtime   [days]  do not operate on files modified less than X days ago.
    --atime   [days]  do not operate on files accessed less than X days ago.
    --ctime   [days]  do not operate on files created less than X days ago.

  DEBUG:
    --dry-run -k    don't commit any action on data 
    --dbg-conf      print deserialized yaml
    --dbg-catch     print regular expression
    --dbg-excl      print deserialized exclusions
";

  #  --anchors [list.txt]   A list of regular expressions, 
  #                          or specifying where to save change logs.
  #                          by default, anchors include the all directories
  #                          specified in config.
sub dbg
{
  my ($foo) = @_;
  {
    local $Data::Dumper::Purity = 1;
    eval Data::Dumper->Dump([$foo], [qw(foo *ary)]);
  }

  my $d = Data::Dumper->new([$foo], [qw(foo *ary)]);
  print $d->Dump;
}

sub logmsg {
  my ($logger, $msg, $verbose, $newline) = @_;

  if ($logger) {
    my $ts = scalar localtime time();
    
    if ($newline) {
      print $logger "[$ts] ";  
    }

    print $logger "$msg";
    $newline and print $logger "\n";
  }
  
  if ($verbose) {
    print "$msg";
    $newline and print "\n"
  }
}

sub is_child_of {
  my ($parent, $dir) = @_;
  (-d $parent) && return (index($dir, $parent) != -1);
  $dir =~ m/$parent/ && return length($dir) > 0;
}

sub commit {
  my (
    $root, $pattern, $verbose,
    $dry, $dbg, $mtimegt, $atimegt, $ctimegt,
    $archive_path, $copy,
    $fd, $exclusions, $dbg_excl,
    $logfd
  ) = @_;

  my $use_archive = 0;
  if ($archive_path) {
    $use_archive=1;
  }
  
  my $dir = $File::Find::dir;
  # bad approach, but we're not worried about speed
  # Return earily if directory is an exclusion
  foreach my $x (@$exclusions) {
    if (is_child_of($x, $dir)) {
      logmsg($logfd, "skipping directory: $dir", $verbose, 1);
      return;
    } 
  }

  if (-e and m/($pattern)/) {
    my $fp = $File::Find::name;
    my $sb = stat($fp);
    $fp =~ s/\n//;
    
    my $now = time();
    
    if ($mtimegt or $atimegt or $ctimegt) {
      foreach (($mtimegt, $sb->mtime), ($atimegt, $sb->atime), ($ctimegt, $sb->ctime)) {
        my ($gt, $ts) = $_;

        foreach my $logger ($logfd, $fd) {
          if ($gt and $now - $ts > $gt) {
            logmsg($logger, "skipping $fp", $verbose, 1);
            return;
          }
        }
      }
    }
    
    if ($verbose) {
      logmsg($logfd, "$fp", $verbose, 0);
      if ($dbg) {
        logmsg($logfd, "-- $pattern", $verbose, 0);
      }
      logmsg($logfd, "\n", $verbose, 0)
    }

    my $operation = "nop";

    if (not $dry) {
      if ($use_archive == 1 && $File::Find::dir) {
        $dir =~ s/$root//;
        
        qx/mkdir -p "$archive_path$dir"/;
        if ($copy) {
          qx/cp $fp "$archive_path$dir"/;
          $operation="copied";
        } else {
          qx/mv $fp "$archive_path$dir"/;
          $operation="moved";
        }
      }

      elsif (-f $fp) {
        unlink($fp);
        $operation="deleted";
      }
      
      elsif (-d $fp) {
        $operation="force deleted";
        qx\rm -rf $fp\;
      }

      else {
        logmsg($logfd, "Unknown operation for $fp", $verbose, 1);
        $operation="nop";
      }
    }

    if ($fd) {
        my $logmsg;

        if ($use_archive) {
          $logmsg = "$fp $operation $archive_path$dir";
        }
        else {
          $logmsg = "$operation $fp";
        }

        logmsg($fd, $logmsg, $verbose, 1);
    }

  }
}

sub prune {
  my (
    $conf, $root, $verbose, 
    $dry, $dbg, $mtimegt, $atimegt, $ctimegt,
    $archive_path, $copy,
    $exclusions, $dbg_excl,
    $generate_change_log,
    $logfd
  ) = @_;
  
  my $today = qx/date --iso-8601/;

  if (! -e $root) {
    logmsg($logfd, "$root doesn't exist");
    exit(1);
  }
  
  while ((my $dir, my $pat_array) = each (%$conf)) {
    my $path;
    my $change_log_fd;

    if ($dir eq "/") { $path=$root; }
    else { $path = "$root/$dir"; }

    if ($generate_change_log == 1) {
      logmsg($logfd, "created $path/CHANGE-LOG-$today.log", $verbose);
      open($change_log_fd, '>', "$path/CHANGE-LOG-$today.log");;
    }

    if (! -d $path) {
      logmsg($logfd, "$dir is not a directory", $verbose);
      next;
    }

    if ($dbg) {
      # Run patterns individually so we know what caught what
      foreach my $pat (@$pat_array) {
        find(sub { commit($root,
          $pat, $verbose, $dry,
          $dbg, $mtimegt, $atimegt, $ctimegt,
          $archive_path,
          $copy, $change_log_fd,
          $exclusions, $dbg_excl, $logfd
          );
        }, $path);
      }
    }

    else {
      my $pattern = join("|", @$pat_array);
      find(sub { commit($root,
        $pattern, $verbose, $dry,
        $dbg, $mtimegt, $atimegt, $ctimegt,
        $archive_path,
        $copy, $change_log_fd,
        $exclusions, $dbg_excl, $logfd);
      }, $path);
    }
    
    if ($change_log_fd) {
      close $change_log_fd;
    }
  }
}

sub load_exclusions {
  my ($file, $array) = @_;

  open my $info, $file or die "Could not open $file: $!";

  while( my $line = <$info> )  {
    $line =~ s/\r?\n//g;
    push @$array, $line;
  }

  close $info;
}

sub die2 {
  print "error: @_\n$USAGE";
  exit 0;
}

sub main {
  my $help_flag = 0;

  my $conf = "";
  my $root = "";

  my $mtimegt = 0;
  my $atimegt = 0;
  my $ctimegt = 0;

  my $archive_path = "";
  my $perfer_copy = 0;

  my $exclusion_fp = "";
  my @exclusions = ();

  my $dbg_catch_flag = 0;
  my $dbg_conf = 0;
  my $dbg_excl = 0;
  my $verbose_flag = 0;
  my $dry_run_flag = 0;

  my $generate_change_log = 0;
  my $log_location = "";
  
  my $logger;
    
  @ARGV == 0 and die2("no args");

  GetOptions(
    'conf|c=s' => \$conf,
    'dir|d=s' => \$root,
    'help|h' => \$help_flag,

    'verbose|v' => \$verbose_flag,
    'dry-run|k' => \$dry_run_flag,
    'dbg-conf' => \$dbg_conf,
    'dbg-catch' => \$dbg_catch_flag,
    'dbg-excl' => \$dbg_excl,
    'change-log' => \$generate_change_log,
    'log|l=s' => \$log_location,
    'archive|a=s' => \$archive_path,
    'copy' => \$perfer_copy,
    
    'mtime=s' => \$mtimegt,
    'atime=s' => \$atimegt,
    'ctime=s' => \$ctimegt,

    'exclude|x=s' => \$exclusion_fp
  );
  $help_flag and die2("none");
  not $root and die2("no directory");
  not $conf and die2("no conf");
  #dbg!($exclusion_fp);
  print "exclude: $exclusion_fp\n";
  length($exclusion_fp) > 0 and load_exclusions($exclusion_fp, \@exclusions);
  
  if ($dbg_excl) {
    print "DEBUG: Exclusion list\n";
    dbg(@exclusions);
  }

  my $prune_map = LoadFile($conf);
  
  $archive_path = abs_path($archive_path);
  $root = abs_path($root);
  
  $log_location && (open($logger, '>', $log_location) or die "couldnt open --log file");

  if ($dbg_conf) {
    dbg($prune_map);
  }

  else {
    prune(
      $prune_map,
      $root,
      $verbose_flag,
      $dry_run_flag,
      $dbg_catch_flag,
      int($mtimegt*60*60*24),
      int($atimegt*60*60*24),
      int($ctimegt*60*60*24),
      $archive_path,
      $perfer_copy,
      \@exclusions,
      $dbg_excl,
      $generate_change_log
    );
  }
}

main()