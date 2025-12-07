set -e

# Credits to @salogiangri UN1CA
HEX_PATCH()
{
    #_CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    #_CHECK_NON_EMPTY_PARAM "FROM" "$2" || return 1
    #_CHECK_NON_EMPTY_PARAM "TO" "$3" || return 1

    local FILE="$1"
    local FROM="$2"
    local TO="$3"

    if [ ! -f "$FILE" ]; then
        #LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    FROM="$(tr "[:upper:]" "[:lower:]" <<< "$FROM")"
    TO="$(tr "[:upper:]" "[:lower:]" <<< "$TO")"

    if ! xxd -p -c 0 "$FILE" | grep -q "$FROM"; then
        #LOGE "No \"$FROM\" match in ${FILE//$WORK_DIR/}"
        return 1
    fi

    #LOG "- Patching \"$FROM\" to \"$TO\" in ${FILE//$WORK_DIR/}"
    xxd -p -c 0 "$FILE" | sed "s/$FROM/$TO/" | xxd -r -p > "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"

    return 0
}

if [ ! -f "$1" ]; then
  echo "cannot find file."
  exit 1
fi

OUT_FILE="$(realpath $1)"

echo "Dest file is $OUT_FILE"

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

magiskboot unpack "$OUT_FILE"
mkdir ramdisk_tmp; cd ramdisk_tmp
magiskboot cpio '../ramdisk.cpio' 'extract system/bin/recovery system/bin/recovery'
magiskboot cpio '../ramdisk.cpio' 'extract system/bin/adbd system/bin/adbd'
magiskboot cpio '../ramdisk.cpio' 'extract system/lib64/libselinux.so system/lib64/libselinux.so'
magiskboot cpio '../ramdisk.cpio' 'extract system/etc/init/hw/init.rc system/etc/init/hw/init.rc'
magiskboot cpio '../ramdisk.cpio' 'extract prop.default prop.default'

# Recovery patches for Samsung AP2A recovery images

# Make SELinux permissive
# FILE: system/lib64/libselinux.so

# Function: security_setenforce
# From: mov w19, w0
# To: mov w19, wzr

HEX_PATCH "system/lib64/libselinux.so" "55d03bd5f303002a" "55d03bd5f3031f2a"

# Bypass package signature verification
# FILE: system/bin/recovery

# Function: verify_package
# From:
#   cmp x8,x9
#   b.ne 0x00203d8c
# To:
#   nop
#   mov w19, #0x1

HEX_PATCH "system/bin/recovery" "1f0109eb81160054" "1f2003d533008052"

# From:
#   cmp x8, x9
#   b.eq 0x00203a44
#   mov w0,#0x2
# To:
#   nop
#   b 0x00203ab0
#   mov w0,#0x2

HEX_PATCH "system/bin/recovery" "1f0109eb6009005440008052" "1f2003d56600001440008052"

# Allow fastbootd
# FILE: system/bin/recovery

# Function: getFastbootdPermission
# From: b.eq 0x00213b88
# To: b 0x00213b88

HEX_PATCH "system/bin/recovery" "2001597ac0000054" "2001597a06000014"

# ADB always root
# FILE: system/bin/adbd

# Function: main
# From: b.ne 0x0019a850
# To: b 0x0019a850

HEX_PATCH "system/bin/adbd" "1f050071e1090054" "1f0500714f000014"

# Enable ADB by default
sed -i 's/persist\.sys\.usb\.config\=mtp/persist\.sys\.usb\.config\=mtp\,adb/g' "prop.default"
sed -i 's/ro\.adb\.secure\=1/ro\.adb\.secure\=0/g' "prop.default"

echo "on boot" >> "system/etc/init/hw/init.rc"
echo "    setprop service.adb.root 1" >> "system/etc/init/hw/init.rc"

magiskboot cpio '../ramdisk.cpio' 'add 755 system/bin/recovery system/bin/recovery'
magiskboot cpio '../ramdisk.cpio' 'add 755 system/bin/adbd system/bin/adbd'
magiskboot cpio '../ramdisk.cpio' 'add 755 system/lib64/libselinux.so system/lib64/libselinux.so'
magiskboot cpio '../ramdisk.cpio' 'add 755 system/etc/init/hw/init.rc system/etc/init/hw/init.rc'
magiskboot cpio '../ramdisk.cpio' 'add 755 prop.default prop.default'

cd ..
PATCHVBMETAFLAG=true magiskboot repack "$OUT_FILE" recovery.img
mv recovery.img "$OUT_FILE"
