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
# using `all` as the directory selector 
# will apply it across all files/directories
#########LEGEND##########
# path/to/directory:
#   - *.log
#   - *.delete_me
#########################
use strict;
use warnings;
use 5.30.0;
use YAML qw(LoadFile DumpFile);
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use File::Find;
Getopt::Long::Configure qw(gnu_getopt);

my $PRUNE_CONF = "prune.yml";
my $ROOT = "/srv/nfs";

my $USAGE = "Usage: ./prune_nfs -d /srv/nfs -c /usr/local/etc/prune_nfs/prune.yml 
  OPTS:
    --conf -c [conf.yml]
    --dir -d [dir/]   
    --help -h         bring up this menu
    --verbose -v      print work
    --dry-run -k      don't delete files 
    --dbg-conf        print deserialized yaml
    --dbg-catch       print what pattern caught the filepath";

sub commit {
  my ($pattern, $verbose, $dry, $dbg) = @_;
  if (-e and m/($pattern)/) {
    if ($verbose) {
      print "$File::Find::name";
      if ($dbg) {
        print " -- $pattern";
      }
      print "\n";
    }

    if (not $dry) {
      if (-f $File::Find::name) {
        unlink($File::Find::name);
      }
      elsif (-d $File::Find::name) {
        rm_dir($File::Find::name)
      }
      else {
        print "Unknown operation for $File::Find::name";
      }
    }

  }
}

sub prune {
  my ($conf, $root, $verbose, $dry, $dbg) = @_;
  # my $conf = LoadFile("prune.yml");
  while ((my $dir, my $pat_array) = each (%$conf)) {
    if (! -d "$root/$dir") {
      print "$dir is not a directory";
      next;
    }

    if ($dbg) {
      # Run patterns individually so we know what caught what
      foreach my $pat (@$pat_array) {
        find(sub { commit($pat, $verbose, $dry, $dbg); }, "$root/$dir");
      }
    }
    else {
      my $pattern = join("|", @$pat_array);
      find(sub { commit($pattern, $verbose, $dry, $dbg); }, "$root/$dir");
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

sub die2 {
  print "error: @_\n$USAGE";
  exit 0;
}

sub main {
  my $conf = "";
  my $root = "";
  my $help_flag = 0;
  my $dbg_flag = 0;
  my $verbose_flag = 0;
  my $dry_run_flag = 0;
  my $dbg_catch_flag = 0;

  @ARGV == 0 and die2("no args");

  GetOptions(
    'conf|c=s' => \$conf,
    'dir|d=s' => \$root,
    'help|h' => \$help_flag,
    'dbg' => \$dbg_flag,
    'verbose|v' => \$verbose_flag,
    'dry-run|k' => \$dry_run_flag,
    'dbg-catch' => \$dbg_catch_flag
  );

  not $root and die2("no directory");
  not $conf and die2("no conf");

  my $ca = LoadFile($conf);

  if ($dbg_flag) {
    dbg(LoadFile($conf));
    exit 0;
  }

  else {
    prune(LoadFile($conf), $root, $verbose_flag, $dry_run_flag, $dbg_catch_flag);
  }
}

main()