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


my $cache = '/Users/cesansim/.p4-fuse/cache';
($cache) = make_path($cache) unless -d $cache;
print STDERR $cache;
die $@ unless -d $cache;


my $c = CHI->new( driver => 'File', root_dir => $cache);
$c->clear();

open my $log, '>>', '/Users/cesansim/.p4-fuse/log';
sub _log {
    print $log (join ', ', (@_, @{[caller(0)]}[2]));
}

my $i = 0;
    
sub p4_do {
    my $p4 = shift;
    my $r = $c->get($p4);
    unless (defined $r) {
	$r = qx|$p4|;
	$c->set($p4, $r, "2 minutes");
    } else {
	_log($p4);
    }
    return $r;
}


sub get_dirs {
    my $file = shift;
    _log($file);
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

sub get_attr_file {
    my $file = shift;
    _log($file);
    my $p4 = p4_do(qq|p4 fstat -Ol -T fileSize,headModTime "$file" 2>/dev/null|);
    $p4 = { map { s/^\.+\s//; split " ", $_ } split /\n/, $p4 };
    return $p4;
}

sub get_attr_dir {
    my $dir = shift;
    _log($dir);
    if ($dir eq '//') { $dir .= '*' } else { $dir .= '/*' }
    my $p4 = p4_do(qq|p4 dirs "$dir" 2>/dev/null|) . "\n" . p4_do(qq|p4 files "$dir" 2>/dev/null|);
    dump $p4;
    return $p4;
}


sub e_getattr {
    my $file = shift;
    _log($file);
    my $type;
    my $attr;
    if ($attr = get_attr_file($file)) {
	_log(dump $attr);
	$type = 0100;
    } elsif ($attr = get_attr_dir($file)) {
	$type = 0040;
    } else {
	return -ENOENT()
    }
    # $type = 0040;
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
    _log($file);
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
