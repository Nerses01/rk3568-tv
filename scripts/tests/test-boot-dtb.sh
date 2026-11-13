#!/bin/sh
# Tests for scripts/boot-dtb.sh. They build a small boot image with the board's layout (FIT header with
# SHA-256s; fdt, kernel and an RSCE resource part with SHA-1s), so they need dtc, fdtget and fdtput: run them
# on the board, or anywhere device-tree-compiler is installed.
# usage: sh scripts/tests/test-boot-dtb.sh   (exit status 0 when all tests pass)
set -u

here=$(cd "$(dirname "$0")" && pwd)
tool=${BOOT_DTB:-$here/../boot-dtb.sh}
for t in dtc fdtget fdtput; do
    command -v "$t" > /dev/null || { echo "SKIP: $t not installed (package device-tree-compiler)"; exit 1; }
done
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
failures=0

check() {   # DESCRIPTION COMMAND...
    desc=$1
    shift
    if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; failures=$((failures + 1)); fi
}
unhex() {
    h=$1
    while [ -n "$h" ]; do
        b=${h%"${h#??}"}
        h=${h#??}
        printf "\\$(printf %03o "0x$b")"
    done
}
le32() { unhex "$(printf %08x "$1" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')"; }
zeros() { head -c "$1" /dev/zero; }
absent() { for f; do [ ! -e "$f" ] || return 1; done; }
put() { dd if="$1" of="$2" bs=65536 seek="$3" oflag=seek_bytes conv=notrunc status=none; }
up512() { echo $((($1 + 511) / 512 * 512)); }
bytes() { echo "$1" | sed 's/../& /g'; }   # hex -> "aa bb ..." for a dts byte string
dtb() { printf '%s\n' "$1" | dtc -q -I dts -O dtb -o "$2" -; }

# entry BLOCK_FILE NAME OFFSET_BLOCKS FILE: one 512-byte RSCE entry block with a SHA-1 of FILE
entry() {
    {
        printf ENTR
        printf %s "$2"
        zeros $((220 - ${#2}))
        unhex "$(sha1sum < "$4" | cut -c1-40)"
        zeros 12
        le32 20
        le32 "$3"
        le32 "$(wc -c < "$4")"
        zeros 244
    } > "$1"
}

# build IMG RK_DTB: a boot image whose fdt is $T/fdt.dtb and whose resource holds RK_DTB and a logo
build() {
    img=$1 rk=$2
    rkblocks=$(($(up512 "$(wc -c < "$rk")") / 512))
    # resource: header block, two entry blocks, rk-kernel.dtb from block 3, the logo after it
    {
        printf RSCE
        zeros 4
        unhex 01010100
        le32 2
        zeros 496
    } > "$T/res.head"
    entry "$T/res.e1" rk-kernel.dtb 3 "$rk"
    entry "$T/res.e2" logo.bmp $((3 + rkblocks)) "$T/logo"
    cat "$T/res.head" "$T/res.e1" "$T/res.e2" > "$T/res"
    cp "$rk" "$T/rk.padded"
    zeros $(($(up512 "$(wc -c < "$rk")") - $(wc -c < "$rk"))) >> "$T/rk.padded"
    cat "$T/rk.padded" "$T/logo" >> "$T/res"

    fpos=2048
    fsize=$(wc -c < "$T/fdt.dtb")
    kpos=$(up512 $((fpos + fsize)))
    ksize=$(wc -c < "$T/kernel")
    rpos=$(up512 $((kpos + ksize)))
    rsize=$(wc -c < "$T/res")
    dtb "/dts-v1/;
/ {
	description = \"test FIT\";
	images {
		fdt { data-size = <$fsize>; data-position = <$fpos>; type = \"flat_dt\";
			hash { value = [$(bytes "$(sha256sum < "$T/fdt.dtb" | cut -c1-64)")]; algo = \"sha256\"; }; };
		kernel { data-size = <$ksize>; data-position = <$kpos>; type = \"kernel\";
			hash { value = [$(bytes "$(sha256sum < "$T/kernel" | cut -c1-64)")]; algo = \"sha256\"; }; };
		resource { data-size = <$rsize>; data-position = <$rpos>; type = \"multi\";
			hash { value = [$(bytes "$(sha256sum < "$T/res" | cut -c1-64)")]; algo = \"sha256\"; }; };
	};
	configurations { default = \"conf\"; conf { fdt = \"fdt\"; kernel = \"kernel\"; multi = \"resource\"; }; };
};" "$T/header.dtb"
    # pad the header to 0x600 bytes, as on the board
    dtc -q -I dtb -O dtb -S 1536 -o "$T/header.padded" "$T/header.dtb"
    zeros $((rpos + rsize + 4096)) > "$img"   # trailing space, like the partition's unused end
    put "$T/header.padded" "$img" 0
    put "$T/fdt.dtb" "$img" "$fpos"
    put "$T/kernel" "$img" "$kpos"
    put "$T/res" "$img" "$rpos"
    echo "$fpos $fsize $kpos $ksize $rpos $rsize" > "$img.layout"
}

head -c 5000 /dev/urandom > "$T/kernel"
head -c 700 /dev/urandom > "$T/logo"
dtb '/dts-v1/; / { model = "fixture"; snd { compatible = "simple-audio-card"; status = "disabled"; }; };' "$T/fdt.dtb"
build "$T/boot.img" "$T/fdt.dtb"
read -r fpos fsize kpos ksize rpos rsize < "$T/boot.img.layout"

# 1. verify: a correct image passes, and every part and entry is checked
sh "$tool" verify "$T/boot.img" > "$T/out" 2>&1
check "verify passes a correct image" [ $? = 0 ]
check "verify checks all three parts and both entries" [ "$(grep -c '^ok ' "$T/out")" = 5 ]

# 2. extract gives the device tree byte for byte
sh "$tool" extract "$T/boot.img" "$T/got.dtb"
check "extract gives the device tree" cmp -s "$T/got.dtb" "$T/fdt.dtb"

# 3. replace with status = "okay" (4 bytes shorter)
cp "$T/fdt.dtb" "$T/okay.dtb"
fdtput -t s "$T/okay.dtb" /snd status okay
sh "$tool" replace "$T/boot.img" "$T/okay.dtb" "$T/new.img" 2> "$T/err"
check "replace exits 0" [ $? = 0 ]
check "the new image has the same size" [ "$(wc -c < "$T/new.img")" = "$(wc -c < "$T/boot.img")" ]
check "the new image passes verify" sh "$tool" verify "$T/new.img" > /dev/null
sh "$tool" extract "$T/new.img" "$T/new.dtb"
check "its device tree is the new one, padded to the old size" [ "$(wc -c < "$T/new.dtb")" = "$fsize" ]
check "its device tree says okay" [ "$(fdtget "$T/new.dtb" /snd status)" = okay ]
dtc -q -I dtb -O dts "$T/okay.dtb" > "$T/a.dts"
dtc -q -I dtb -O dts "$T/new.dtb" > "$T/b.dts"
check "its device tree decompiles to the same source as the input" cmp -s "$T/a.dts" "$T/b.dts"
tail -c +$((rpos + 1)) "$T/new.img" | head -c "$rsize" > "$T/new.res"
check "rk-kernel.dtb in the resource part is the same new device tree" \
    sh -c "tail -c +$((3 * 512 + 1)) '$T/new.res' | head -c $fsize | cmp -s - '$T/new.dtb'"
# only the header, the fdt, the rk-kernel.dtb entry's checksum and rk-kernel.dtb itself may change
cmp -l "$T/boot.img" "$T/new.img" | awk -v f="$fpos" -v fs="$fsize" -v r="$rpos" '
    { o = $1 - 1
      if (o < 1536 || (o >= f && o < f + fs) || (o >= r + 512 + 224 && o < r + 512 + 244) ||
          (o >= r + 1536 && o < r + 1536 + fs)) next
      print "unexpected change at " o; bad = 1 }
    END { exit bad }' > "$T/changes"
check "nothing else changed (kernel, logo, other entries, the unused end)" [ ! -s "$T/changes" ]

# 4. a larger device tree doesn't fit: refused, no output
dtb '/dts-v1/; / { model = "fixture"; big = "0123456789012345678901234567890123456789012345678901234567890123456789"; snd { status = "okay"; }; };' "$T/big.dtb"
sh "$tool" replace "$T/boot.img" "$T/big.dtb" "$T/big.img" 2> "$T/err"
check "a larger device tree is refused" [ $? = 1 ]
check "  and says why" grep -q "more than the $fsize" "$T/err"
check "  and writes nothing" absent "$T/big.img" "$T/big.img.part"

# 5. a corrupted image fails verify, and replace refuses it
cp "$T/boot.img" "$T/bad.img"
printf X | dd of="$T/bad.img" bs=1 seek=$((kpos + 100)) conv=notrunc status=none
sh "$tool" verify "$T/bad.img" > "$T/out" 2>&1
check "verify fails a corrupted kernel" [ $? = 1 ]
check "  and names it" grep -q '^BAD  kernel' "$T/out"
sh "$tool" replace "$T/bad.img" "$T/okay.dtb" "$T/x.img" 2> "$T/err"
check "replace refuses a corrupted image" [ $? = 1 ]
check "  and writes nothing" absent "$T/x.img" "$T/x.img.part"

# 6. the two copies differ (both with valid checksums): replace refuses to pick one
cp "$T/okay.dtb" "$T/other.dtb"
build "$T/differ.img" "$T/other.dtb"
check "an image whose copies differ still verifies" sh "$tool" verify "$T/differ.img" > /dev/null
sh "$tool" replace "$T/differ.img" "$T/okay.dtb" "$T/y.img" 2> "$T/err"
check "replace refuses when the two copies differ" [ $? = 1 ]
check "  and says why" grep -q "differ" "$T/err"

# 7. a file that isn't a device tree is refused
printf 'not a dtb' > "$T/junk"
sh "$tool" replace "$T/boot.img" "$T/junk" "$T/z.img" 2> "$T/err"
check "a non-device-tree file is refused" [ $? = 1 ]
check "  and says why" grep -q "not a device tree" "$T/err"

echo "$failures failure(s)"
[ "$failures" = 0 ]
