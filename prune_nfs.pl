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
use 5.28.1;
use YAML qw(LoadFile DumpFile);
use Data::Dumper;
use Getopt::Long qw(GetOptions);
use File::Find;
use Cwd qw(getcwd abs_path);
use File::Path qw(make_path remove_tree);
Getopt::Long::Configure qw(gnu_getopt);

my $USAGE = "Usage: ./prune_nfs -d /srv/nfs -c /usr/local/etc/prune_nfs/prune.yml 
  OPTS:
    --dir -d [dir/]
    --conf -c [conf.yml]  configuration file - see prune.yml
    --archive -a [dir/]   archive instead of deleting
    --mtimegt -m [days]   modify time greater than in days
    
    --copy          copy instead of moving when archiving
    --help -h       bring up this menu
    --verbose -v    print work
    --dry-run -k    don't delete files 
    --dbg-conf      print deserialized yaml
    --dbg-catch     print what pattern caught the filepath";

sub commit {
  my ($root, $pattern, $verbose, $dry, $dbg, $mtimegt, $archive_path, $copy) = @_;
  my $use_archive = 0;
  if ($archive_path) {
    #qx/mkdir -p $archive_path/;
    $use_archive=1;
  }
  
  if (-e and m/($pattern)/) {
    my $fp = $File::Find::name;
    # my $sb = stat($File::Find::name);
    # my $now = time();

    # print "TIMESTAMP: %s [$now]\n", $sb->mtime;
    # if (! $now - $sb->mtime > $mtimegt) {
    #   return;
    # }

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
        
        if ($copy) {
          qx/cp $fp $archive_path$dir/;
        } else {
          qx/"mv $fp $archive_path$dir"/;
        }
      }
      elsif (-f $fp) {
        unlink($fp);
      }
      elsif (-d $fp) {
        qx\rm -rf $File::Find::name\
      }
      else {
        print "Unknown operation for $File::Find::name";
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

sub die2 {
  print "error: @_\n$USAGE";
  exit 0;
}

sub main {
  my $conf = "";
  my $root = "";
  my $help_flag = 0;
  my $verbose_flag = 0;
  my $dry_run_flag = 0;
  my $modified_epoch_gt = 0;
  my $perfer_copy = 0;
  my $archive_path = "";

  my $dbg_catch_flag = 0;
  my $dbg_conf = 0;

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
    'copy' => \$perfer_copy
  );

  not $root and die2("no directory");
  not $conf and die2("no conf");

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