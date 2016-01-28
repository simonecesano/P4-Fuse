#!/usr/bin/perl -w
use strict;
use feature qw(say state current_sub);
use English;

use strict;
use warnings;

use Fuse;
use POSIX qw(ENOTDIR ENOENT ENOSYS EEXIST EPERM O_RDONLY O_RDWR O_APPEND O_CREAT setsid);
use Sub::Identify ':all';
use Data::Dump qw/dump/;

use File::Basename;

$\ = "\n"; $, = "; "; $|++;
my ($mountpoint) = "";
$mountpoint = shift(@ARGV) if @ARGV;
die unless $mountpoint;

use Data::Dumper;

#use blib;
use Fuse qw(fuse_get_context);
use POSIX qw(ENOENT EISDIR EINVAL);
use CHI;
use File::Path qw(make_path remove_tree);

my $cache = '~/.p4-fuse/cache';
($cache) = make_path($cache) unless -d $cache;
my $c = CHI->new( driver => 'File', root_dir => $cache);
$c->clear();

my $i = 0;
    
sub p4_do {
    my $p4 = shift;
    my $r = $c->get($p4);
    unless (defined $r) {
	$r = qx|$p4|;
	$c->set($p4, $r, "2 minutes");
    } else {
	print STDERR $p4;
    }
    return $r;
}


sub get_dirs {
    my $file = shift;
    print STDERR $file;
    my $file_re = quotemeta('//'); 
    if ($file eq '//') { $file .= '*' } else { $file .= '/*' }
    my $dirs = p4_do(qq|p4 dirs "$file" 2>/dev/null|);
    my @dirs = (grep { /\w/ } map { s/^\s+|\s$//g; s/^$file_re//; $_ } split /\n/, $dirs);
    return @dirs;
}

sub get_files {
    my $file = shift;
    my $file_re = quotemeta('//'); 
    if ($file eq '//') { $file .= '*' } else { $file .= '/*' }
    my $files = p4_do(qq|p4 files -e "$file" 2>/dev/null|);
    my @files = (grep { /\w/ } map { s/^\s+|\s$//g; s/^$file_re//; s/#.+//; $_ } split /\n/, $files);
    return @files;
}


sub e_getattr {
    my $file = shift;
    print $file;
    
    my $type = 0040;
    my $mode = 0755;
    my $size = 1024;
    
    my ($modes) = ($type << 9) + $mode;
    my ($dev, $ino, $rdev, $blocks, $gid, $uid, $nlink, $blksize) = (0,0,0,1,0,0,1,1024);
    my ($atime, $ctime, $mtime);
    
    $atime = $ctime = $mtime = time;
    
    return ($dev,$ino,$modes,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);
}

sub e_getdir {
    my $file = shift;
    print $file;
    $file =~ s|^/|//|;
    my $file_re = quotemeta(substr($file, 2). '/');
    my @dirs = get_dirs($file);
    my @files = get_files($file);

    my @dirs_and_files = map { basename($_) } (@dirs, @files);
    return (@dirs_and_files, 0);
}

sub e_statfs { return 255, 1, 1, 1, 1, 2 }

# If you run the script directly, it will run fusermount, which will in turn
# re-run this script.  Hence the funky semantics.
Fuse::main(
	mountpoint=>$mountpoint,
	getattr=>"main::e_getattr",
	getdir =>"main::e_getdir",
	statfs =>"main::e_statfs",
	threaded=>0
);

print $PROCESS_ID;
