#!/usr/bin/perl
# vivo Office Kit (pcsuite) 7.0.5 arm64 China build -> English.
# Applies patch/edits.dat to Contents/Resources/app.asar of the installed app.
# Uses only modules that ship with macOS's /usr/bin/perl.
#
#   perl patcher.pl status  [--app /path/to/pcsuite.app]
#   perl patcher.pl install [--app /path/to/pcsuite.app]
#   perl patcher.pl restore [--app /path/to/pcsuite.app]
#
# Exit codes: 0 ok, 2 app not found, 3 unsupported build, 4 permission denied, 1 other error.
use strict; use warnings;
use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(decode_base64);
use File::Basename qw(dirname);
use File::Copy qw(move);
use Cwd qw(abs_path);

my $BLOCK = 4 * 1024 * 1024;
my $here  = dirname(abs_path($0));
my $cmd   = shift(@ARGV) // 'status';
my ($app, $data) = (undef, "$here/patch/edits.dat");
while (@ARGV) { my $a = shift @ARGV; if ($a eq '--app') { $app = shift @ARGV } elsif ($a eq '--data') { $data = shift @ARGV } }
if (!defined $app) { ($app) = grep { -d $_ } ('/Applications/pcsuite.app', '/Applications/pcsuite.localized/pcsuite.app'); }
fail(2, "vivo Office Kit (pcsuite.app) was not found in /Applications. Install it first.") unless defined $app && -d "$app/Contents/Resources";
my $res = "$app/Contents/Resources";
my ($asar, $backup) = ("$res/app.asar", "$res/app.asar.zh-backup");
fail(2, "app.asar not found in $res") unless -f $asar;

sub fail { my ($code, $msg) = @_; print STDERR "$msg\n"; exit $code; }

sub read_header {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return;
    read($fh, my $head, 16) == 16 or return;
    my ($four, $hsize, undef, $jlen) = unpack('V4', $head);
    return unless $four == 4;
    read($fh, my $raw, $jlen) == $jlen or return;
    close $fh;
    return ($raw, 8 + $hsize);
}

open(my $df, '<', $data) or fail(1, "Cannot read $data");
my $first = <$df>; chomp $first;
my ($magic, $orig_hdr_sha, $new_hdr_sha, $ver) = split /\t/, $first;
fail(1, "Unrecognised patch data file") unless defined $magic && $magic eq 'V1';

my ($raw, $base) = read_header($asar);
my $cur = defined $raw ? sha256_hex($raw) : '';
my $state = $cur eq $orig_hdr_sha ? 'original' : $cur eq $new_hdr_sha ? 'patched' : 'unknown';

if ($state eq 'unknown' && -f $backup) { my ($b) = read_header($backup); $state = 'patched' if defined $b && sha256_hex($b) eq $orig_hdr_sha; }
if ($cmd eq 'status') { print "$state\n$app\n"; exit 0; }

if ($cmd eq 'restore') {
    fail(1, "No backup of the original archive was found; nothing to restore.") unless -f $backup;
    rename($backup, $asar) or fail($!{EACCES} || $!{EPERM} ? 4 : 1, "Could not restore: $!");
    print "Restored the original Chinese version.\n"; exit 0;
}
fail(1, "Unknown command '$cmd'") unless $cmd eq 'install';

my $source = $asar;
if ($state ne 'original') {
    my ($braw, $bbase) = -f $backup ? read_header($backup) : ();
    if (defined $braw && sha256_hex($braw) eq $orig_hdr_sha) { ($raw, $base, $source) = ($braw, $bbase, $backup); }
    else { fail(3, "This copy of vivo Office Kit is not the build this patch was made for (7.0.5 arm64 China). Nothing was changed."); }
}

# ---- read the edit list
my (@files, $curf);
while (my $line = <$df>) {
    chomp $line; next unless length $line;
    my @f = split /\t/, $line, -1;
    if ($f[0] eq 'F') { $curf = { path => $f[1], off => $f[2], size => $f[3], osha => $f[4], nsize => $f[5], nsha => $f[6], hoff => $f[7], hlen => $f[8], edits => [] }; push @files, $curf; }
    elsif ($f[0] eq 'E') { push @{ $curf->{edits} }, [ $f[1], $f[2], decode_base64($f[3] // '') ]; }
}
close $df;

# ---- build the patched files in memory
open(my $in, '<:raw', $source) or fail(1, "Cannot open $source: $!");
my $cursor = (-s $source) - $base;
for my $f (@files) {
    seek($in, $base + $f->{off}, 0);
    read($in, my $o, $f->{size}) == $f->{size} or fail(3, "Unexpected end of archive while reading $f->{path}");
    fail(3, "$f->{path} does not match the expected original. Nothing was changed.") unless sha256_hex($o) eq $f->{osha};
    my ($n, $pos) = ('', 0);
    for my $e (@{ $f->{edits} }) { $n .= substr($o, $pos, $e->[0] - $pos) . $e->[2]; $pos = $e->[0] + $e->[1]; }
    $n .= substr($o, $pos);
    fail(1, "Internal check failed for $f->{path}. Nothing was changed.") unless length($n) == $f->{nsize} && sha256_hex($n) eq $f->{nsha};
    my @blocks; for (my $i = 0; $i < length($n); $i += $BLOCK) { push @blocks, '"' . sha256_hex(substr($n, $i, $BLOCK)) . '"'; }
    $f->{data}  = $n;
    $f->{entry} = '{"size":' . length($n) . ',"integrity":{"algorithm":"SHA256","hash":"' . sha256_hex($n) . '","blockSize":' . $BLOCK . ',"blocks":[' . join(',', @blocks) . ']},"offset":"' . $cursor . '"}';
    $cursor += length($n);
}
for my $f (sort { $b->{hoff} <=> $a->{hoff} } @files) { substr($raw, $f->{hoff}, $f->{hlen}) = $f->{entry}; }
fail(1, "Internal check failed for the archive index. Nothing was changed.") unless sha256_hex($raw) eq $new_hdr_sha;

# ---- write the new archive next to the old one, then swap
my $tmp = "$asar.tmp-english";
my $padded = $raw . ("\0" x ((4 - length($raw) % 4) % 4));
my $hbuf = pack('VV', 4 + length($padded), length($raw)) . $padded;
open(my $out, '>:raw', $tmp) or fail($!{EACCES} || $!{EPERM} ? 4 : 1, "Cannot write to $res: $!");
print $out pack('VV', 4, length($hbuf)), $hbuf;
seek($in, $base, 0);
while (read($in, my $buf, 16 * 1024 * 1024)) { print $out $buf or fail(1, "Write failed: $!"); }
print $out $_->{data} for @files;
close($out) or fail(1, "Write failed: $!");
close $in;
my @st = stat($source);
chmod($st[2] & 07777, $tmp); chown($st[4], $st[5], $tmp);
if ($source eq $asar) { rename($asar, $backup) or do { unlink $tmp; fail($!{EACCES} || $!{EPERM} ? 4 : 1, "Could not back up the original: $!"); }; }
rename($tmp, $asar) or do { rename($backup, $asar) if $source eq $asar; unlink $tmp; fail($!{EACCES} || $!{EPERM} ? 4 : 1, "Could not install the patched archive: $!"); };
print "English patch installed (" . scalar(@files) . " files). Original kept as app.asar.zh-backup.\n";
exit 0;
