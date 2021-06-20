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

my $USAGE = "Usage: ./prune_nfs -d /srv/nfs -c /usr/local/etc/prune_nfs/prune.yml 
  OPTS:
    --help -h       bring up this menu
    --verbose -v    print work

    --dir -d [dir]          prune directory
    --conf -c [conf.yml]    configuration file - see prune.yml
    --mtimegt -m [days]     filter files modified greater than X days.
    --archive -a [dir] [--copy] archive instead of deleting, 
                                --copy will copy the
                                files instead of moving it.
    
    --dry-run -k    don't commit any action on data 
    --dbg-conf      print deserialized yaml
    --dbg-catch     print regular expression";

sub commit {
  my ($root, $pattern, $verbose, $dry, $dbg, $mtimegt, $archive_path, $copy) = @_;
  my $use_archive = 0;
  if ($archive_path) {
    $use_archive=1;
  }
  
  if (-e and m/($pattern)/) {
    my $fp = $File::Find::name;
    my $sb = stat($fp);
    #dbg($sb);
    $fp =~ s/\n//;
    
    my $now = time();
    my $timestamp = scalar $sb->mtime;

    if ($now - $sb->mtime < $mtimegt) {
      return;
    }

    if ($verbose) {
      print "$fp";
      if ($dbg) {
        print " -- $pattern";
      }
      print "\n";
    }


    if (not $dry) {
      if ($use_archive == 1 && $File::Find::dir) {
        my $dir = $File::Find::dir;
        $dir =~ s/$root//;

        qx/mkdir -p "$archive_path$dir"/;
        if ($copy) {
          qx/cp $fp "$archive_path$dir"/;
        } else {
          qx/mv $fp "$archive_path$dir"/;
        }
      }
      elsif (-f $fp) {
        unlink($fp);
      }
      elsif (-d $fp) {
        qx\rm -rf $fp\
      }
      else {
        print "Unknown operation for $fp";
      }
    }
  }
}

sub prune {
  my ($conf, $root, $verbose, $dry, $dbg, $mtimegt, $archive_path, $copy) = @_;
  if (! -e $root) {
    print "$root\ndoesn't exist\n";
    exit(1);
  }
  
  while ((my $dir, my $pat_array) = each (%$conf)) {
    my $path;
    
    if ($dir eq "/") { $path=$root; }
    else { $path = "$root/$dir"; }

    if (! -d $path) {
      print "$dir is not a directory\n";
      next;
    }

    if ($dbg) {
      # Run patterns individually so we know what caught what
      foreach my $pat (@$pat_array) {
        find(sub { commit($root, $pat, $verbose, $dry, $dbg, $mtimegt, $archive_path, $copy); }, $path);
      }
    }
    else {
      my $pattern = join("|", @$pat_array);
      find(sub { commit($root, $pattern, $verbose, $dry, $dbg, $mtimegt, $archive_path, $copy); }, $path);
    }
  }
}

sub dbg
{
  my ($conf) = @_;
  {
    local $Data::Dumper::Purity = 1;
    eval Data::Dumper->Dump([$conf], [qw(foo *ary)]);
  }

  my $d = Data::Dumper->new([$conf], [qw(foo *ary)]);
  print $d->Dump;
}

sub load_exclusions {
  my $file = @_;
  open my $info, $file or die "Could not open $file: $!";

  while( my $line = <$info>)  {   
    $line =~ s/\n|//;
  
    #last if $. == 2;
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

  my $modified_epoch_gt = 0;
  
  my $archive_path = "";
  my $perfer_copy = 0;

  my $exclusion_fp = "";
  my @exclusions = ();

  my $dbg_catch_flag = 0;
  my $dbg_conf = 0;
  my $verbose_flag = 0;
  my $dry_run_flag = 0;
  
  @ARGV == 0 and die2("no args");

  GetOptions(
    'conf|c=s' => \$conf,
    'dir|d=s' => \$root,
    'help|h' => \$help_flag,
    'verbose|v' => \$verbose_flag,
    'dry-run|k' => \$dry_run_flag,
    'dbg-conf' => \$dbg_conf,
    'dbg-catch' => \$dbg_catch_flag,
    'archive|a=s' => \$archive_path,
    'mtimegt|m=s' => \$modified_epoch_gt,
    'exclude|x=s' => $exclusion_fp,
    'copy' => \$perfer_copy
  );

  not $root and die2("no directory");
  not $conf and die2("no conf");

  $exclusion_fp and load_exclusions($exclusion_fp, \@exclusions)
  
  my $settings = LoadFile($conf);
  
  $archive_path = abs_path($archive_path);
  $root = abs_path($root);
  
  if ($dbg_conf) {
    dbg($settings);
  }

  else {
    prune(
      $settings,
      $root,
      $verbose_flag,
      $dry_run_flag,
      $dbg_catch_flag,
      int($modified_epoch_gt*60*60*24),
      $archive_path,
      $perfer_copy
    );
  }
}

main()