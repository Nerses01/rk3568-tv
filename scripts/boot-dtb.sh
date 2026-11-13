#!/bin/sh
# Read or replace the device tree in this board's boot image (the `boot` partition; step 0.4).
#
# The image is a FIT: a small FDT header at offset 0 lists three parts by absolute position (`data-position`,
# `data-size`), each with a SHA-256 in the header: `fdt` (the kernel's device tree), `kernel` and `resource`.
# `resource` is Rockchip's RSCE container: 512-byte blocks, a header block, then one block per entry
# ("ENTR", name[220], hash[32], hash size, offset in blocks, size in bytes), holding the boot logos and
# `rk-kernel.dtb`, a second copy of the device tree. Each entry has a SHA-1. `replace` puts a new device tree
# into both places, pads it to the old size so that nothing moves, and updates all four checksums.
# See docs/02-board.md, "Changing the device tree".
#
# usage: boot-dtb.sh verify  BOOT_IMG                    check every checksum; exit 1 on a mismatch
#        boot-dtb.sh extract BOOT_IMG OUT_DTB            write the device tree
#        boot-dtb.sh replace BOOT_IMG NEW_DTB OUT_IMG    write a copy of BOOT_IMG with NEW_DTB in it
#
# Needs fdtget and fdtput (device-tree-compiler), sha1sum, sha256sum, od, dd, head, tail.
set -u

die() { echo "boot-dtb: $*" >&2; exit 1; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

hex() { od -A n -t x1 -v | tr -d ' \n'; }   # bytes on stdin -> lowercase hex
unhex() {                                    # hex string -> bytes on stdout
    h=$1
    while [ -n "$h" ]; do
        b=${h%"${h#??}"}
        h=${h#??}
        printf "\\$(printf %03o "0x$b")"
    done
}
be32() { od -A n -t u1 -j "$2" -N 4 "$1" | awk '{ print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }'; }
le32() { od -A n -t u1 -j "$2" -N 4 "$1" | awk '{ print $1 + $2 * 256 + $3 * 65536 + $4 * 16777216 }'; }
put() {   # SRC DEST OFFSET: write SRC over DEST from byte OFFSET on
    dd if="$1" of="$2" bs=65536 seek="$3" oflag=seek_bytes conv=notrunc status=none || die "cannot write $2"
}
pad() {   # FILE SIZE: append zeros up to SIZE and set the FDT's totalsize to SIZE (FDT allows free space)
    n=$(wc -c < "$1")
    [ "$n" -le "$2" ] || die "internal: $1 is $n bytes, more than $2"
    head -c $(($2 - n)) /dev/zero >> "$1"
    unhex "$(printf %08x "$2")" > "$tmp/totalsize"
    put "$tmp/totalsize" "$1" 4
}

# --- the FIT header
load_header() {   # BOOT_IMG -> $tmp/header.dtb, $hsize
    [ -r "$1" ] || die "$1: cannot read it"   # a file, or the partition itself (/dev/mmcblk2p3)
    [ "$(head -c 4 "$1" | hex)" = d00dfeed ] || die "$1: not a FIT image (no FDT header)"
    hsize=$(be32 "$1" 4)
    head -c "$hsize" "$1" > "$tmp/header.dtb"
    fdtget "$tmp/header.dtb" /images/fdt data-position > /dev/null 2>&1 ||
        die "$1: no /images/fdt with a data-position"
}
pos() { fdtget -t u "$tmp/header.dtb" "/images/$1" data-position; }
size() { fdtget -t u "$tmp/header.dtb" "/images/$1" data-size; }
header_sha256() { for b in $(fdtget -t bx "$tmp/header.dtb" "/images/$1/hash" value); do printf %02x "0x$b"; done; }
part() { tail -c +"$(($(pos "$2") + 1))" "$1" | head -c "$(size "$2")"; }   # IMG NAME -> stdout

# --- the RSCE container
entries() {   # RES -> lines "block name offset_blocks size hash_size"
    [ "$(head -c 4 "$1" | hex)" = 52534345 ] || die "resource part: not an RSCE container"
    n=$(le32 "$1" 12)
    i=0
    while [ "$i" -lt "$n" ]; do
        o=$(((1 + i) * 512))
        name=$(tail -c +$((o + 5)) "$1" | head -c 220 | tr -d '\000')
        echo "$((1 + i)) $name $(le32 "$1" $((o + 260))) $(le32 "$1" $((o + 264))) $(le32 "$1" $((o + 256)))"
        i=$((i + 1))
    done
}
entry_hash() {   # RES BLOCK HASH_SIZE -> stored hash, hex
    tail -c +$(($2 * 512 + 225)) "$1" | head -c "$3" | hex
}
content() { tail -c +$(($2 * 512 + 1)) "$1" | head -c "$3"; }   # RES OFFSET_BLOCKS SIZE -> stdout
digest() {   # HASH_SIZE: hash stdin with SHA-1 (20) or SHA-256 (32)
    case $1 in
    20) sha1sum | cut -d' ' -f1 ;;
    32) sha256sum | cut -d' ' -f1 ;;
    *) die "resource entry hash of $1 bytes: unknown" ;;
    esac
}

verify() {   # BOOT_IMG
    load_header "$1"
    bad=0
    for name in $(fdtget -l "$tmp/header.dtb" /images); do
        algo=$(fdtget "$tmp/header.dtb" "/images/$name/hash" algo 2>/dev/null)
        [ "$algo" = sha256 ] || die "/images/$name: hash algorithm '$algo'; only sha256 is supported"
        if [ "$(part "$1" "$name" | sha256sum | cut -d' ' -f1)" = "$(header_sha256 "$name")" ]; then
            echo "ok   $name"
        else
            echo "BAD  $name"
            bad=1
        fi
    done
    part "$1" resource > "$tmp/res.verify"
    entries "$tmp/res.verify" > "$tmp/entries"
    while read -r blk name off sz hs; do
        if [ "$hs" = 0 ]; then
            echo "--   resource/$name (no checksum)"
        elif [ "$(content "$tmp/res.verify" "$off" "$sz" | digest "$hs")" = "$(entry_hash "$tmp/res.verify" "$blk" "$hs")" ]; then
            echo "ok   resource/$name"
        else
            echo "BAD  resource/$name"
            bad=1
        fi
    done < "$tmp/entries"
    [ "$bad" = 0 ]
}

extract() {   # BOOT_IMG OUT_DTB
    load_header "$1"
    part "$1" fdt > "$2" || die "cannot write $2"
}

replace() {   # BOOT_IMG NEW_DTB OUT_IMG
    img=$1 new=$2 out=$3
    [ -f "$new" ] || die "$new: no such file"
    [ "$(head -c 4 "$new" | hex)" = d00dfeed ] || die "$new: not a device tree blob"
    verify "$img" > "$tmp/verify.before" || die "$img: its checksums don't match; refusing to change it"
    load_header "$img"
    fsize=$(size fdt)
    nsize=$(wc -c < "$new")
    [ "$nsize" -le "$fsize" ] || die "$new: $nsize bytes, more than the $fsize the image has room for"

    part "$img" fdt > "$tmp/fdt.old"
    part "$img" resource > "$tmp/res"
    entries "$tmp/res" > "$tmp/entries"
    set -- $(grep ' rk-kernel\.dtb ' "$tmp/entries")
    [ "$#" = 5 ] || die "$img: no rk-kernel.dtb in the resource part"
    blk=$1 off=$3 esize=$4 hs=$5
    content "$tmp/res" "$off" "$esize" | cmp -s - "$tmp/fdt.old" ||
        die "$img: rk-kernel.dtb and the FIT's fdt differ; refusing to pick one"

    cp "$new" "$tmp/fdt.new"
    pad "$tmp/fdt.new" "$fsize"

    # the resource part: new rk-kernel.dtb and its entry checksum
    put "$tmp/fdt.new" "$tmp/res" $((off * 512))
    digest "$hs" < "$tmp/fdt.new" > "$tmp/sum"
    unhex "$(cat "$tmp/sum")" > "$tmp/sum.bin"
    put "$tmp/sum.bin" "$tmp/res" $((blk * 512 + 224))

    # the FIT header: checksums of fdt and resource (same length, so the header keeps its size)
    # shellcheck disable=SC2046
    fdtput -t bx "$tmp/header.dtb" /images/fdt/hash value $(sha256sum < "$tmp/fdt.new" | cut -c1-64 | sed 's/../& /g') ||
        die "cannot update the fdt checksum"
    # shellcheck disable=SC2046
    fdtput -t bx "$tmp/header.dtb" /images/resource/hash value $(sha256sum < "$tmp/res" | cut -c1-64 | sed 's/../& /g') ||
        die "cannot update the resource checksum"
    pad "$tmp/header.dtb" "$hsize"

    cp "$img" "$out.part" || die "cannot write $out.part"
    put "$tmp/header.dtb" "$out.part" 0
    put "$tmp/fdt.new" "$out.part" "$(pos fdt)"
    put "$tmp/res" "$out.part" "$(pos resource)"
    verify "$out.part" > "$tmp/verify.after" || { cat "$tmp/verify.after" >&2; die "the new image fails its own checks"; }
    mv "$out.part" "$out" || die "cannot write $out"
}

case ${1:-} in
verify) [ "$#" = 2 ] || die "usage: boot-dtb.sh verify BOOT_IMG"; verify "$2" ;;
extract) [ "$#" = 3 ] || die "usage: boot-dtb.sh extract BOOT_IMG OUT_DTB"; extract "$2" "$3" ;;
replace) [ "$#" = 4 ] || die "usage: boot-dtb.sh replace BOOT_IMG NEW_DTB OUT_IMG"; replace "$2" "$3" "$4" ;;
*) die "usage: boot-dtb.sh verify|extract|replace ... (see the comment at the top)" ;;
esac
