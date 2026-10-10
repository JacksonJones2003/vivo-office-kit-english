#!/usr/bin/perl
# vivo Office Kit (pcsuite) for Mac, China edition -> English.
# Rewrites Contents/Resources/app.asar of the installed app. Uses only modules that ship with macOS's perl.
#
#   perl patcher.pl status  [--app /path/to/pcsuite.app]
#   perl patcher.pl install [--app /path/to/pcsuite.app]
#   perl patcher.pl restore [--app /path/to/pcsuite.app]
#
# Each file inside the archive is handled on its own:
#   full  - the file is byte-for-byte the one this patch was built from (7.0.5): the exact,
#           checksum-verified edit list in patch/edits.dat is applied.
#   basic - the file differs (another version): the language lock is found by pattern and removed,
#           which switches the app to vivo's own built-in English. Untested on other versions.
#
# `status` prints four lines: state (original|patched|unsupported), app path, mode (full|basic|none), detail.
# Exit codes: 0 ok, 2 app not found, 3 unsupported build, 4 permission denied, 1 other error.
use strict; use warnings;
use Digest::SHA qw(sha256_hex);
use MIME::Base64 qw(decode_base64);
use JSON::PP;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $PATCH_VERSION = '1.1.0';
my $BLOCK  = 4 * 1024 * 1024;
my $MARK   = ";(function(){try{\n/* English patch";   # start of patch/main_prefix.js
my $DIST   = 'dist/electron';
my @RENDER = ('renderer.js', 'child-window.js', 'module-share-preview.js');

my $here = dirname(abs_path($0));
my $cmd  = shift(@ARGV) // 'status';
my ($app, $pdir) = (undef, "$here/patch");
while (@ARGV) { my $a = shift @ARGV; if ($a eq '--app') { $app = shift @ARGV } elsif ($a eq '--patch') { $pdir = shift @ARGV } }
if (!defined $app) { ($app) = grep { -d $_ } ('/Applications/pcsuite.app', '/Applications/pcsuite.localized/pcsuite.app'); }

sub fail { my ($code, $msg) = @_; print STDERR "$msg\n"; exit $code; }
sub perm { return ($!{EACCES} || $!{EPERM}) ? 4 : 1; }

fail(2, "vivo Office Kit (pcsuite.app) was not found in /Applications. Install it first.") unless defined $app && -d "$app/Contents/Resources";
my $res = "$app/Contents/Resources";
my ($asar, $backup, $marker) = ("$res/app.asar", "$res/app.asar.zh-backup", "$res/app.asar.english-patch");
fail(2, "app.asar not found in $res") unless -f $asar;

# ---------------------------------------------------------------- archive helpers
sub read_header {
    my ($path) = @_;
    open(my $fh, '<:raw', $path) or return;
    read($fh, my $head, 16) == 16 or return;
    my ($four, $hsize, undef, $jlen) = unpack('V4', $head);
    return unless $four == 4 && $jlen > 2;
    read($fh, my $raw, $jlen) == $jlen or return;
    close $fh;
    my $tree = eval { JSON::PP->new->utf8->decode($raw) };
    return unless ref $tree eq 'HASH';
    return { raw => $raw, base => 8 + $hsize, tree => $tree, path => $path };
}
sub node_of {
    my ($hdr, $rel) = @_;
    my $n = $hdr->{tree};
    for my $part (split m{/}, $rel) { return unless ref $n eq 'HASH' && ref $n->{files} eq 'HASH'; $n = $n->{files}{$part}; }
    return unless ref $n eq 'HASH' && !exists $n->{files} && defined $n->{offset} && !$n->{unpacked};
    return $n;
}
sub read_file {
    my ($hdr, $node) = @_;
    open(my $fh, '<:raw', $hdr->{path}) or return;
    seek($fh, $hdr->{base} + $node->{offset}, 0);
    my $size = 0 + $node->{size}; my $buf = '';
    if ($size > 0) { read($fh, $buf, $size) == $size or return; }
    close $fh; return $buf;
}
sub is_patched {   # does this archive carry our marker code at the top of main.js?
    my ($hdr) = @_;
    my $n = node_of($hdr, "$DIST/main.js") or return 0;
    open(my $fh, '<:raw', $hdr->{path}) or return 0;
    seek($fh, $hdr->{base} + $n->{offset}, 0); read($fh, my $buf, length $MARK); close $fh;
    return defined $buf && $buf eq $MARK ? 1 : 0;
}

# ---------------------------------------------------------------- patch data
sub load_edits {
    my %by;
    open(my $df, '<', "$pdir/edits.dat") or fail(1, "Cannot read $pdir/edits.dat");
    my $first = <$df>; fail(1, "Unrecognised patch data file") unless defined $first && $first =~ /^V1\t/;
    my $cur;
    while (my $line = <$df>) {
        chomp $line; next unless length $line;
        my @f = split /\t/, $line, -1;
        if ($f[0] eq 'F') { $cur = { osha => $f[4], nsize => $f[5], nsha => $f[6], edits => [] }; $by{ $f[1] } = $cur; }
        elsif ($f[0] eq 'E') { push @{ $cur->{edits} }, [ $f[1], $f[2], $f[3] // '' ]; }
    }
    close $df; return \%by;
}
sub slurp { my ($p) = @_; open(my $fh, '<:raw', $p) or fail(1, "Cannot read $p"); local $/; my $d = <$fh>; close $fh; return $d; }

# ---------------------------------------------------------------- per-file patching
sub apply_exact {
    my ($o, $e) = @_;
    my ($n, $pos) = ('', 0);
    for my $ed (@{ $e->{edits} }) { $n .= substr($o, $pos, $ed->[0] - $pos) . decode_base64($ed->[2]); $pos = $ed->[0] + $ed->[1]; }
    $n .= substr($o, $pos);
    return (length($n) == $e->{nsize} && sha256_hex($n) eq $e->{nsha}) ? $n : undef;
}
# Pattern-based unlock for versions the edit list was not built from. Returns (new content, rules applied, core ok).
sub apply_basic {
    my ($name, $c) = @_;
    my $w = qr/[\w\$]+/; my ($n, $core) = (0, 0);
    if (grep { $_ eq $name } @RENDER) {
        my $a = ($c =~ s/(function $w\(\)\{if\(!$w\)return")zh_CN(";const)/$1en_US$2/g) || 0;
        my $b = ($c =~ s/(=$w\?$w\(\):")zh_CN(",$w=new $w\.default\(\{locale:$w,fallbackLocale:)$w\?"en_US":"zh_CN"/$1en_US$2"en_US"/g) || 0;
        $core = ($a && $b) ? 1 : 0; $n += $a + $b;
        $n += ($c =~ s/lang:null!==\(($w)=$w\.default\.getItem\("currentLanguage"\)\)&&void 0!==\1\?\1:"zh_CN"/lang:"en_US"/g) || 0;
        $n += ($c =~ s/&lang=\$\{this\.lang\}/&lang=en_US/g) || 0 if $name eq 'renderer.js';
    }
    if ($name eq 'main.js' || grep { $_ eq $name } @RENDER) {
        $n += ($c =~ s/init\(\)\{(const $w=!($w)\.default\.getItem\("useLogin"\),$w=!$w\.default\.getItem\("currentLanguage"\);)/init(){if(1){this._currentLanguage="en_US";this._isRtl=!1;try{"en_US"!==$2.default.getItem("currentLanguage")&&($2.default.setItem("currentLanguage","en_US"),$2.default.setItem("vLang","vus"),$2.default.setItem("isRtl",!1))}catch(e){}return}$1/g) || 0;
    }
    if ($name eq 'main.js') {
        $n += ($c =~ s/"undefined"!=typeof __buildConfig__&&__buildConfig__\.IS_EXPORT\?($w\.getLocalesJson\("framework"\)):(?:\{\}|null)/$1/g) || 0;
        $n += ($c =~ s/(getLocalesJson=$w=>\{const $w=)$w\.default\.getItem\("currentLanguage"\)\|\|"en_US"/$1"en_US"/g) || 0;
        if (index($c, $MARK) != 0 && $c =~ /\A\s*(?:module\.exports|\(function|!function|"use strict")/) { my $p = slurp("$pdir/main_prefix.js"); $p =~ s/\n+\z//; $c = "$p\n$c"; $n++; $core = 1; }
    }
    if ($name eq 'locales-en_US.js') {
        my (%anch, %keys);
        open(my $lf, '<', "$pdir/locale_extra.tsv") or return ($c, 0, 0);
        while (my $l = <$lf>) { chomp $l; my @f = split /\t/, $l, -1; if ($f[0] eq 'M') { $anch{ $f[1] } = [ split /,/, $f[2] ] } elsif ($f[0] eq 'K') { push @{ $keys{ $f[1] } }, [ $f[2], decode_base64($f[3]) ] } }
        close $lf;
        my @lits; while ($c =~ /JSON\.parse\('([^'\\]*(?:\\.[^'\\]*)*)'\)/gs) { push @lits, [ $-[1], $+[1] ]; }
        my @ins;
        for my $mod (keys %keys) {
            my ($best, $score) = (undef, 1);
            for my $lit (@lits) { my $txt = substr($c, $lit->[0], $lit->[1] - $lit->[0]); my $s = grep { index($txt, "\"$_\":") >= 0 } @{ $anch{$mod} || [] }; if ($s > $score) { ($best, $score) = ($lit, $s) } }
            next unless $best;
            my $txt = substr($c, $best->[0], $best->[1] - $best->[0]);
            next unless $txt =~ /\}\z/ && length($txt) > 2;
            my $add = join('', map { ',' . $_->[1] } grep { index($txt, "\"$_->[0]\":") < 0 } @{ $keys{$mod} });
            push @ins, [ $best->[1] - 1, $add ] if length $add;
        }
        for my $i (sort { $b->[0] <=> $a->[0] } @ins) { substr($c, $i->[0], 0) = $i->[1]; $n++; }
    }
    return ($c, $n, $core);
}

# Decide, for one source archive, what would be changed. Returns { mode, detail, files => [ [rel, node, newdata] ] }.
sub plan {
    my ($hdr) = @_;
    my $edits = load_edits();
    my %targets = map { $_ => 1 } keys %$edits;
    $targets{"$DIST/$_"} = 1 for (@RENDER, 'main.js', 'locales-en_US.js');
    my @out; my ($full, $basic, $rules, $core_r, $core_m) = (0, 0, 0, 0, 0);
    for my $rel (sort keys %targets) {
        my $node = node_of($hdr, $rel) or next;
        my $o = read_file($hdr, $node); next unless defined $o;
        my $name = (split m{/}, $rel)[-1];
        my $e = $edits->{$rel};
        my $n;
        if ($e && !$ENV{VOK_FORCE_BASIC} && sha256_hex($o) eq $e->{osha}) { $n = apply_exact($o, $e); }
        if (defined $n) { $full++; $core_r = 1 if $name eq 'renderer.js'; $core_m = 1 if $name eq 'main.js'; }
        else {
            my ($c, $cnt, $core) = apply_basic($name, $o);
            next unless $cnt;
            $n = $c; $basic++; $rules += $cnt;
            $core_r = 1 if $name eq 'renderer.js' && $core; $core_m = 1 if $name eq 'main.js' && $core;
        }
        push @out, [ $rel, $node, $n ];
    }
    my $mode = !$core_r ? 'none' : $basic ? 'basic' : 'full';
    my $detail = $mode eq 'none' ? 'the language lock was not found in this version'
               : $mode eq 'full' ? "$full files fully patched"
               : "$full files fully patched, $basic by pattern ($rules changes)";
    return { mode => $mode, detail => $detail, files => \@out, main_ok => $core_m };
}

# ---------------------------------------------------------------- work out where we stand
my $cur = read_header($asar) or fail(3, "app.asar could not be read as an Electron archive. Nothing was changed.");
my $cur_patched = is_patched($cur);
my $bak = (-f $backup) ? read_header($backup) : undef;
$bak = undef if $bak && is_patched($bak);
my $source = $cur_patched ? $bak : $cur;      # the pristine archive to build from (undef if we have none)

if ($cmd eq 'status') {
    my $p = $source ? plan($source) : { mode => 'none', detail => 'patched, but the original backup is missing' };
    my $state = $cur_patched ? 'patched' : ($p->{mode} eq 'none' ? 'unsupported' : 'original');
    print "$state\n$app\n$p->{mode}\n$p->{detail}\n"; exit 0;
}

if ($cmd eq 'restore') {
    fail(1, "The English patch is not installed, so there is nothing to restore.") unless $cur_patched;
    fail(1, "The backup of the original archive is missing. Reinstall vivo Office Kit from vivo's installer to restore it.") unless $bak;
    rename($backup, $asar) or fail(perm(), "Could not restore: $!");
    unlink $marker;
    print "Restored the original Chinese version.\n"; exit 0;
}
fail(1, "Unknown command '$cmd'") unless $cmd eq 'install';
fail(3, "The English patch is installed but its backup of the original is missing, so it cannot be rebuilt. Reinstall vivo Office Kit, then run this again.") unless $source;

my $p = plan($source);
fail(3, "This version of vivo Office Kit is too different for the patch (the language lock was not found). Nothing was changed.") if $p->{mode} eq 'none';

# ---------------------------------------------------------------- build the new archive index
my $raw = $source->{raw};
my $cursor = (-s $source->{path}) - $source->{base};
my $surgery = $ENV{VOK_FORCE_REENCODE} ? 0 : 1;
my @repl;
for my $f (@{ $p->{files} }) {
    my ($rel, $node, $n) = @$f;
    my @blocks; for (my $i = 0; $i < length($n); $i += $BLOCK) { push @blocks, sha256_hex(substr($n, $i, $BLOCK)); }
    @blocks = (sha256_hex('')) unless @blocks;
    my $oldhash = ref $node->{integrity} eq 'HASH' ? ($node->{integrity}{hash} // '') : '';
    my ($oldsize, $oldoff) = ($node->{size}, $node->{offset});
    $node->{size} = length($n); $node->{offset} = "$cursor";
    $node->{integrity} = { algorithm => 'SHA256', hash => sha256_hex($n), blockSize => $BLOCK, blocks => \@blocks };
    my $entry = '{"size":' . length($n) . ',"integrity":{"algorithm":"SHA256","hash":"' . sha256_hex($n) . '","blockSize":' . $BLOCK . ',"blocks":[' . join(',', map { "\"$_\"" } @blocks) . ']},"offset":"' . $cursor . '"}';
    $cursor += length($n);
    next unless $surgery;
    # Keep the index byte-for-byte as vivo wrote it except for this entry, when the entry can be located unambiguously.
    my $needle = "\"hash\":\"$oldhash\""; my $at = length($oldhash) == 64 ? index($raw, $needle) : -1;
    if ($at < 0 || index($raw, $needle, $at + 1) >= 0) { $surgery = 0; next; }
    my $start = rindex($raw, '{"size":', $at); my $tail = "\"offset\":\"$oldoff\"}"; my $end = index($raw, $tail, $at);
    if ($start < 0 || $end < 0 || $end - $start > 200000 || substr($raw, $start, 40) !~ /\A\{"size":\Q$oldsize\E,"integrity":\{/) { $surgery = 0; next; }
    push @repl, [ $start, $end + length($tail) - $start, $entry ];
}
if ($surgery) { for my $r (sort { $b->[0] <=> $a->[0] } @repl) { substr($raw, $r->[0], $r->[1]) = $r->[2]; } }
else { $raw = JSON::PP->new->utf8->canonical->encode($source->{tree}); }
my $check = eval { JSON::PP->new->utf8->decode($raw) };
fail(1, "Internal check failed for the archive index. Nothing was changed.") unless ref $check eq 'HASH';

# ---------------------------------------------------------------- write next to the old one, verify, then swap
my $tmp = "$asar.tmp-english";
my $padded = $raw . ("\0" x ((4 - length($raw) % 4) % 4));
my $hbuf = pack('VV', 4 + length($padded), length($raw)) . $padded;
open(my $in, '<:raw', $source->{path}) or fail(1, "Cannot open $source->{path}: $!");
open(my $out, '>:raw', $tmp) or fail(perm(), "Cannot write to $res: $!");
print $out pack('VV', 4, length($hbuf)), $hbuf;
seek($in, $source->{base}, 0);
while (read($in, my $buf, 16 * 1024 * 1024)) { print $out $buf or fail(1, "Write failed: $!"); }
print $out $_->[2] for @{ $p->{files} };
close($out) or fail(1, "Write failed: $!");
close $in;

my $new = read_header($tmp);
my $ok = $new ? 1 : 0;
if ($ok) { for my $f (@{ $p->{files} }) { my $n = node_of($new, $f->[0]); my $d = $n ? read_file($new, $n) : undef; unless (defined $d && $d eq $f->[2]) { $ok = 0; last; } } }
if ($ok) { my $n = node_of($new, 'package.json'); my $d = $n ? read_file($new, $n) : undef; $ok = 0 unless defined $d && ref(eval { JSON::PP->new->utf8->decode($d) }) eq 'HASH'; }
unless ($ok) { unlink $tmp; fail(1, "The rebuilt archive failed verification. Nothing was changed."); }

my @st = stat($source->{path});
chmod($st[2] & 07777, $tmp); chown($st[4], $st[5], $tmp);
if (!$cur_patched) { rename($asar, $backup) or do { unlink $tmp; fail(perm(), "Could not back up the original: $!"); }; }
rename($tmp, $asar) or do { rename($backup, $asar) unless $cur_patched; unlink $tmp; fail(perm(), "Could not install the patched archive: $!"); };
if (open(my $mf, '>', $marker)) { print $mf "patch=$PATCH_VERSION\nmode=$p->{mode}\ndetail=$p->{detail}\n"; close $mf; chown($st[4], $st[5], $marker); }

if ($p->{mode} eq 'full') { print "English patch installed ($p->{detail}). The original is kept as a backup.\n"; }
else { print "English patch installed in basic mode ($p->{detail}). This version differs from the one the patch was built for, so some screens may stay in Chinese. The original is kept as a backup.\n"; }
exit 0;
