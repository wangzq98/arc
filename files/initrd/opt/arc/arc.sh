#!/usr/bin/env bash

[[ -z "${ARC_PATH}" || ! -d "${ARC_PATH}/include" ]] && ARC_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. ${ARC_PATH}/include/functions.sh
. ${ARC_PATH}/include/addons.sh
. ${ARC_PATH}/include/modules.sh
. ${ARC_PATH}/include/storage.sh
. ${ARC_PATH}/include/network.sh

[ -z "${LOADER_DISK}" ] && die "Loader Disk not found!"

# Memory: Check Memory installed
RAMTOTAL=0
while read -r LINE; do
  RAMSIZE=${LINE}
  RAMTOTAL=$((${RAMTOTAL} + ${RAMSIZE}))
done < <(dmidecode -t memory | grep -i "Size" | cut -d" " -f2 | grep -i "[1-9]")
RAMTOTAL=$((${RAMTOTAL} * 1024))
RAMMAX=$((${RAMTOTAL} * 2))
RAMMIN=$((${RAMTOTAL} / 2))

# Check for Hypervisor
if grep -q "^flags.*hypervisor.*" /proc/cpuinfo; then
  # Check for Hypervisor
  MACHINE="$(lscpu | grep Hypervisor | awk '{print $3}')"
else
  MACHINE="NATIVE"
fi

# Get Loader Disk Bus
BUS=$(getBus "${LOADER_DISK}")

# Set Warning to 0
WARNON=0

# Get DSM Data from Config
MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
LAYOUT="$(readConfigKey "layout" "${USER_CONFIG_FILE}")"
KEYMAP="$(readConfigKey "keymap" "${USER_CONFIG_FILE}")"
LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
if [ -n "${MODEL}" ]; then
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  DT="$(readModelKey "${MODEL}" "dt")"
fi

# Get Arc Data from Config
DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
BOOTCOUNT="$(readConfigKey "arc.bootcount" "${USER_CONFIG_FILE}")"
CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
BOOTIPWAIT="$(readConfigKey "arc.bootipwait" "${USER_CONFIG_FILE}")"
BOOTWAIT="$(readConfigKey "arc.bootwait" "${USER_CONFIG_FILE}")"
REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
KERNELPANIC="$(readConfigKey "arc.kernelpanic" "${USER_CONFIG_FILE}")"
MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
ODP="$(readConfigKey "arc.odp" "${USER_CONFIG_FILE}")"
HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
STATICIP="$(readConfigKey "arc.staticip" "${USER_CONFIG_FILE}")"

###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="${ARC_TITLE} |"
  if [ -n "${MODEL}" ]; then
    BACKTITLE+=" ${MODEL}"
  else
    BACKTITLE+=" (no model)"
  fi
  BACKTITLE+=" |"
  if [ -n "${PRODUCTVER}" ]; then
    BACKTITLE+=" ${PRODUCTVER}"
  else
    BACKTITLE+=" (no version)"
  fi
  BACKTITLE+=" |"
  if [ -n "${IP}" ]; then
    BACKTITLE+=" ${IP}"
  else
    BACKTITLE+=" (no IP)"
  fi
  BACKTITLE+=" |"
  if [ "${ARCPATCH}" = "arc" ]; then
    BACKTITLE+=" Patch: A"
  elif [ "${ARCPATCH}" = "random" ]; then
    BACKTITLE+=" Patch: R"
  elif [ "${ARCPATCH}" = "user" ]; then
    BACKTITLE+=" Patch: U"
  fi
  BACKTITLE+=" |"
  if [ "${CONFDONE}" = "true" ]; then
    BACKTITLE+=" Config: Y"
  else
    BACKTITLE+=" Config: N"
  fi
  BACKTITLE+=" |"
  if [ "${BUILDDONE}" = "true" ]; then
    BACKTITLE+=" Build: Y"
  else
    BACKTITLE+=" Build: N"
  fi
  BACKTITLE+=" |"
  BACKTITLE+=" ${MACHINE}(${BUS^^})"
  echo "${BACKTITLE}"
}

###############################################################################
# Make Model Config
function arcMenu() {
  # Loop menu
  RESTRICT=1
  FLGBETA=0
  dialog --backtitle "$(backtitle)" --title "Model" --aspect 18 \
    --infobox "Reading models" 3 20
    echo -n "" >"${TMP_PATH}/modellist"
    while read -r M; do
      Y="$(readModelKey "${M}" "disks")"
      echo "${M} ${Y}" >>"${TMP_PATH}/modellist"
    done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sed 's/.*\///; s/\.yml//')

    while true; do
      echo -n "" >"${TMP_PATH}/menu"
      FLGNEX=0
      while read -r M Y; do
        PLATFORM=$(readModelKey "${M}" "platform")
        DT="$(readModelKey "${M}" "dt")"
        BETA="$(readModelKey "${M}" "beta")"
        [[ "${BETA}" = "true" && ${FLGBETA} -eq 0 ]] && continue
        DISKS="$(readModelKey "${M}" "disks")-Bay"
        ARCCONF="$(readModelKey "${M}" "arc.serial")"
        if [ -n "${ARCCONF}" ]; then
          ARCAV="Arc"
        else
          ARCAV="NonArc"
        fi
        if [[ "${PLATFORM}" = "r1000" || "${PLATFORM}" = "v1000" || "${PLATFORM}" = "epyc7002" ]]; then
          CPU="AMD"
        else
          CPU="Intel"
        fi
        # Check id model is compatible with CPU
        COMPATIBLE=1
        if [ ${RESTRICT} -eq 1 ]; then
          for F in "$(readModelArray "${M}" "flags")"; do
            if ! grep -q "^flags.*${F}.*" /proc/cpuinfo; then
              COMPATIBLE=0
              FLGNEX=1
              break
            fi
          done
        fi
        [ "${DT}" = "true" ] && DT="DT" || DT=""
        [ "${BETA}" = "true" ] && BETA="Beta" || BETA=""
        [ ${COMPATIBLE} -eq 1 ] && echo "${M} \"$(printf "\Zb%-7s\Zn \Zb%-6s\Zn \Zb%-13s\Zn \Zb%-3s\Zn \Zb%-7s\Zn \Zb%-4s\Zn" "${DISKS}" "${CPU}" "${PLATFORM}" "${DT}" "${ARCAV}" "${BETA}")\" ">>"${TMP_PATH}/menu"
      done < <(cat "${TMP_PATH}/modellist" | sort -n -k 2)
    [ ${FLGBETA} -eq 0 ] && echo "b \"\Z1Show beta Models\Zn\"" >>"${TMP_PATH}/menu"
    [ ${FLGNEX} -eq 1 ] && echo "f \"\Z1Show incompatible Models \Zn\"" >>"${TMP_PATH}/menu"
    dialog --backtitle "$(backtitle)" --colors --menu "Choose Model for Loader" 0 62 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ "${resp}" = "b" ]; then
      FLGBETA=1
      continue
    fi
    if [ "${resp}" = "f" ]; then
      RESTRICT=0
      continue
    fi
    break
  done
  # read model config for dt and aes
  if [ "${MODEL}" != "${resp}" ]; then
    MODEL="${resp}"
    # Check for AES
    if ! grep -q "^flags.*aes.*" /proc/cpuinfo; then
      WARNON=4
    fi
    PRODUCTVER=""
    writeConfigKey "model" "${MODEL}" "${USER_CONFIG_FILE}"
    writeConfigKey "productver" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.mac1" "" "${USER_CONFIG_FILE}"
    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
      # Delete old files
      rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
    fi
  fi
  arcbuild
}

###############################################################################
# Shows menu to user type one or generate randomly
function arcbuild() {
  # read model values for arcbuild
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  if [ "${ARCRECOVERY}" != "true" ]; then
    # Select Build for DSM
    ITEMS="$(readConfigEntriesArray "productvers" "${MODEL_CONFIG_PATH}/${MODEL}.yml" | sort -r)"
    if [ -z "${1}" ]; then
      dialog --clear --no-items --backtitle "$(backtitle)" \
        --menu "Choose a Version" 0 0 0 ${ITEMS} 2>"${TMP_PATH}/resp"
      resp="$(<"${TMP_PATH}/resp")"
      [ -z "${resp}" ] && return 1
    else
      if ! arrayExistItem "${1}" ${ITEMS}; then return; fi
      resp="${1}"
    fi
    if [ "${PRODUCTVER}" != "${resp}" ]; then
      PRODUCTVER="${resp}"
      writeConfigKey "productver" "${PRODUCTVER}" "${USER_CONFIG_FILE}"
      if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
        # Delete old files
        rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
      fi
    fi
  fi
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Config" \
    --infobox "Reconfiguring Synoinfo, Addons and Modules" 0 0
  # Delete synoinfo and reload model/build synoinfo
  writeConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  while IFS=': ' read -r KEY VALUE; do
    writeConfigKey "synoinfo.\"${KEY}\"" "${VALUE}" "${USER_CONFIG_FILE}"
  done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].synoinfo")
  # Rebuild modules
  writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  while read -r ID DESC; do
    writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
  done < <(getAllModules "${PLATFORM}" "${KVER}")
  if [ "${ONLYVERSION}" != "true" ]; then
    arcsettings
  else
    # Build isn't done
    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    # Ask for Build
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Build now?" 0 0 0 \
      1 "Yes - Build Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      make
    elif [ ${resp} -eq 2 ]; then
      dialog --clear --no-items --backtitle "$(backtitle)"
      return 1
    fi
  fi
}

###############################################################################
# Make Arc Settings
function arcsettings() {
  # Read Model Values
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readModelKey "${MODEL}" "dt")"
  ARCCONF="$(readConfigKey "arc.serial" "${MODEL_CONFIG_PATH}/${MODEL}.yml")"
  if [ "${ARCRECOVERY}" = "true" ]; then
    writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
  elif [[ "${ARCRECOVERY}" != "true" && -n "${ARCCONF}" ]]; then
    dialog --clear --backtitle "$(backtitle)" --title "Arc Patch Model"\
      --menu "Do you want to use Syno Services?" 7 50 0 \
      1 "Yes - Install with Arc Patch" \
      2 "No - Install with random Serial/Mac" \
      3 "No - Install with my Serial/Mac" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      # Read Arc Patch from File
      SN="$(readModelKey "${MODEL}" "arc.serial")"
      writeConfigKey "arc.patch" "arc" "${USER_CONFIG_FILE}"
      writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      # Generate random Serial
      SN="$(generateSerial "${MODEL}")"
      writeConfigKey "arc.patch" "random" "${USER_CONFIG_FILE}"
      writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 3 ]; then
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --inputbox "Please enter a valid Serial " 0 0 "" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break 2
        SN="$(cat ${TMP_PATH}/resp)"
        if [ -z "${SN}" ]; then
          return
        elif [ $(validateSerial ${MODEL} ${SN}) -eq 1 ]; then
          break
        fi
        # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
        break
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --yesno "Invalid Serial, continue?" 0 0
        [ $? -eq 0 ] && break
      done
      writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
      writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    fi
    writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
  elif [[ "${ARCRECOVERY}" != "true" && -z "${ARCCONF}" ]]; then
    dialog --clear --backtitle "$(backtitle)" --title "Non Arc Patch Model" \
      --menu "Please select an Option?" 7 50 0 \
      1 "Install with random Serial/Mac" \
      2 "Install with my Serial/Mac" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      # Generate random Serial
      SN="$(generateSerial "${MODEL}")"
      writeConfigKey "arc.patch" "random" "${USER_CONFIG_FILE}"
      writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    elif [ ${resp} -eq 2 ]; then
      while true; do
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --inputbox "Please enter a serial number " 0 0 "" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && break 2
        SN="$(cat ${TMP_PATH}/resp)"
        if [ -z "${SN}" ]; then
          return
        elif [ $(validateSerial ${MODEL} ${SN}) -eq 1 ]; then
          break
        fi
        # At present, the SN rules are not complete, and many SNs are not truly invalid, so not provide tips now.
        break
        dialog --backtitle "$(backtitle)" --colors --title "Serial" \
          --yesno "Invalid Serial, continue?" 0 0
        [ $? -eq 0 ] && break
      done
      writeConfigKey "arc.patch" "user" "${USER_CONFIG_FILE}"
      writeConfigKey "addons.cpuinfo" "" "${USER_CONFIG_FILE}"
    fi
    writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
  fi
  ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
  # Get Network Config for Loader
  getnet
  if [ "${ONLYPATCH}" = "true" ]; then
    return 1
  fi
  # Get Portmap for Loader
  getmap
  # Check Warnings
  if [ ${WARNON} -eq 1 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your Controller has more then 8 Disks connected. Max Disks per Controller: 8" 0 0
  fi
  if [ ${WARNON} -eq 3 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: You have more then 8 Ethernet Ports. There are only 8 supported by DSM." 0 0
  fi
  if [ ${WARNON} -eq 4 ]; then
    dialog --backtitle "$(backtitle)" --title "Arc Warning" \
      --msgbox "WARN: Your CPU does not have AES Support for Hardwareencryption in DSM." 0 0
  fi
  # Select Addons
  addonSelection
  # Config is done
  writeConfigKey "arc.confdone" "true" "${USER_CONFIG_FILE}"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  # Ask for Build
  dialog --clear --backtitle "$(backtitle)" \
    --menu "Build now?" 0 0 0 \
    1 "Yes - Build Arc Loader now" \
    2 "No - I want to make changes" \
  2>"${TMP_PATH}/resp"
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && return 1
  if [ ${resp} -eq 1 ]; then
    make
  elif [ ${resp} -eq 2 ]; then
    dialog --clear --no-items --backtitle "$(backtitle)"
    return 1
  fi
}

###############################################################################
# Building Loader
function make() {
  # Read Config
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  # Memory: Set mem_max_mb to the amount of installed memory to bypass Limitation
  writeConfigKey "synoinfo.mem_max_mb" "${RAMMAX}" "${USER_CONFIG_FILE}"
  writeConfigKey "synoinfo.mem_min_mb" "${RAMMIN}" "${USER_CONFIG_FILE}"
  # Check if all addon exists
  while IFS=': ' read -r ADDON PARAM; do
    [ -z "${ADDON}" ] && continue
    if ! checkAddonExist "${ADDON}" "${PLATFORM}" "${KVER}"; then
      dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
        --msgbox "Addon ${ADDON} not found!" 0 0
      return 1
    fi
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  # Update PAT Data
  PAT_URL_CONF="$(readConfigKey "arc.paturl" "${USER_CONFIG_FILE}")"
  PAT_HASH_CONF="$(readConfigKey "arc.pathash" "${USER_CONFIG_FILE}")"
  if [[ -z "${PAT_URL_CONF}" || -z "${PAT_HASH_CONF}" ]]; then
    PAT_URL_CONF="0"
    PAT_HASH_CONF="0"
  fi
  while true; do
    dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
      --infobox "Get PAT Data from Syno..." 3 30
    idx=0
    while [ ${idx} -le 3 ]; do # Loop 3 times, if successful, break
      PAT_URL="$(curl -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].url')"
      PAT_HASH="$(curl -skL "https://www.synology.com/api/support/findDownloadInfo?lang=en-us&product=${MODEL/+/%2B}&major=${PRODUCTVER%%.*}&minor=${PRODUCTVER##*.}" | jq -r '.info.system.detail[0].items[0].files[0].checksum')"
      PAT_URL=${PAT_URL%%\?*}
      if [[ -n "${PAT_URL}" && -n "${PAT_HASH}" ]]; then
        break
      fi
      sleep 1
      idx=$((${idx} + 1))
    done
    if [[ -z "${PAT_URL}" || -z "${PAT_HASH}" ]]; then
      MSG="Failed to get PAT Data.\nPlease manually fill in the URL and Hash of PAT."
      PAT_URL=""
      PAT_HASH=""
    else
      MSG="Successfully got PAT Data.\nPlease confirm or modify as needed."
    fi
    dialog --backtitle "$(backtitle)" --colors --title "Arc Build" \
      --extra-button --extra-label "Retry" --default-button "OK" \
      --form "${MSG}" 10 110 2 "URL" 1 1 "${PAT_URL}" 1 7 100 0 "HASH" 2 1 "${PAT_HASH}" 2 7 100 0 \
      2>"${TMP_PATH}/resp"
    RET=$?
    [ ${RET} -eq 0 ] && break    # ok-button
    return                       # 1 or 255  # cancel-button or ESC
  done
  PAT_URL="$(cat "${TMP_PATH}/resp" | sed -n '1p')"
  PAT_HASH="$(cat "${TMP_PATH}/resp" | sed -n '2p')"
  if [[ "${PAT_HASH}" != "${PAT_HASH_CONF}" || ! -f "${ORI_ZIMAGE_FILE}" || ! -f "${ORI_RDGZ_FILE}" ]]; then
    writeConfigKey "arc.paturl" "${PAT_URL}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.pathash" "${PAT_HASH}" "${USER_CONFIG_FILE}"
    # Check for existing Files
    mkdir -p "${UNTAR_PAT_PATH}"
    DSM_FILE="${UNTAR_PAT_PATH}/${PAT_HASH}.tar"
    # Get new Files
    DSM_URL="https://raw.githubusercontent.com/AuxXxilium/arc-dsm/main/files/${MODEL}/${PRODUCTVER}/${PAT_HASH}.tar"
    STATUS=$(curl --insecure -s -w "%{http_code}" -L "${DSM_URL}" -o "${DSM_FILE}")
    if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
      dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
      --msgbox "No DSM Image found!\nTry Syno Link." 0 0
      # Grep PAT_URL
      PAT_FILE="${TMP_PATH}/${PAT_HASH}.pat"
      STATUS=$(curl -k -w "%{http_code}" -L "${PAT_URL}" -o "${PAT_FILE}" --progress-bar)
      if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
        dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
          --msgbox "No DSM Image found!\ Exit." 0 0
        return 1
      fi
      # Extract Files
      header=$(od -bcN2 ${PAT_FILE} | head -1 | awk '{print $3}')
      case ${header} in
          105)
          echo "Uncompressed tar"
          isencrypted="no"
          ;;
          213)
          echo "Compressed tar"
          isencrypted="no"
          ;;
          255)
          echo "Encrypted"
          isencrypted="yes"
          ;;
          *)
          echo -e "Could not determine if pat file is encrypted or not, maybe corrupted, try again!"
          ;;
      esac
      if [ "${isencrypted}" = "yes" ]; then
        # Uses the extractor to untar PAT file
        LD_LIBRARY_PATH="${EXTRACTOR_PATH}" "${EXTRACTOR_PATH}/${EXTRACTOR_BIN}" "${PAT_FILE}" "${UNTAR_PAT_PATH}"
      else
        # Untar PAT file
        tar -xf "${PAT_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
      fi
      # Cleanup PAT Download
      rm -f "${PAT_FILE}"
      dialog --backtitle "$(backtitle)" --title "DSM Extraction" --aspect 18 \
      --msgbox "DSM Extraction successful!" 0 0
    elif [ -f "${DSM_FILE}" ]; then
      tar -xf "${DSM_FILE}" -C "${UNTAR_PAT_PATH}" >"${LOG_FILE}" 2>&1
      dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
        --msgbox "DSM Image Download successful!" 0 0
    else
      dialog --backtitle "$(backtitle)" --title "DSM Download" --aspect 18 \
        --msgbox "ERROR: No DSM Image found!" 0 0
    fi
    # Copy DSM Files to Locations if DSM Files not found
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART1_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART1_PATH}"
    cp -f "${UNTAR_PAT_PATH}/grub_cksum.syno" "${PART2_PATH}"
    cp -f "${UNTAR_PAT_PATH}/GRUB_VER" "${PART2_PATH}"
    cp -f "${UNTAR_PAT_PATH}/zImage" "${ORI_ZIMAGE_FILE}"
    cp -f "${UNTAR_PAT_PATH}/rd.gz" "${ORI_RDGZ_FILE}"
    rm -rf "${UNTAR_PAT_PATH}"
  fi
  # Reset Bootcount if User rebuild DSM
  if [[ -z "${BOOTCOUNT}" || ${BOOTCOUNT} -gt 0 ]]; then
    writeConfigKey "arc.bootcount" "0" "${USER_CONFIG_FILE}"
  fi
  clear
  livepatch
  sleep 3
  if [[ -f "${ORI_ZIMAGE_FILE}" && -f "${ORI_RDGZ_FILE}" && -f "${MOD_ZIMAGE_FILE}" && -f "${MOD_RDGZ_FILE}" ]]; then
    # Build is done
    writeConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
    writeConfigKey "arc.builddone" "true" "${USER_CONFIG_FILE}"
    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
    # Ask for Boot
    dialog --clear --backtitle "$(backtitle)" \
      --menu "Build done. Boot now?" 0 0 0 \
      1 "Yes - Boot Arc Loader now" \
      2 "No - I want to make changes" \
    2>"${TMP_PATH}/resp"
    resp="$(<"${TMP_PATH}/resp")"
    [ -z "${resp}" ] && return 1
    if [ ${resp} -eq 1 ]; then
      boot && exit 0
    elif [ ${resp} -eq 2 ]; then
      dialog --clear --no-items --backtitle "$(backtitle)"
      return 1
    fi
  else
    dialog --backtitle "$(backtitle)" --title "Error" --aspect 18 \
      --msgbox "Build failed!\nPlease check your Connection and Diskspace!" 0 0
    return 1
  fi
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "$(backtitle)" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    [ $? -ne 0 ] && return 1
    mv -f "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
    ERRORS=$(yq eval "${USER_CONFIG_FILE}" 2>&1)
    [ $? -eq 0 ] && break
    dialog --backtitle "$(backtitle)" --title "Invalid YAML format" --msgbox "${ERRORS}" 0 0
  done
  OLDMODEL="${MODEL}"
  OLDPRODUCTVER="${PRODUCTVER}"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  SN="$(readConfigKey "arc.sn" "${USER_CONFIG_FILE}")"
  if [[ "${MODEL}" != "${OLDMODEL}" || "${PRODUCTVER}" != "${OLDPRODUCTVER}" ]]; then
    # Delete old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  fi
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Shows option to manage Addons
function addonMenu() {
  addonSelection
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

function addonSelection() {
  # read platform and kernel version to check if addon exists
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  # read addons from user config
  unset ADDONS
  declare -A ADDONS
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && ADDONS["${KEY}"]="${VALUE}"
  done < <(readConfigMap "addons" "${USER_CONFIG_FILE}")
  rm -f "${TMP_PATH}/opts"
  touch "${TMP_PATH}/opts"
  while read -r ADDON DESC; do
    arrayExistItem "${ADDON}" "${!ADDONS[@]}" && ACT="on" || ACT="off"
    echo -e "${ADDON} \"${DESC}\" ${ACT}" >>"${TMP_PATH}/opts"
  done < <(availableAddons "${PLATFORM}" "${KVER}")
  dialog --backtitle "$(backtitle)" --title "Loader Addons" --aspect 18 \
    --checklist "Select Loader Addons to include.\nPlease read Wiki before choosing anything.\nSelect with SPACE, Confirm with ENTER!" 0 0 0 \
    --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  resp="$(<"${TMP_PATH}/resp")"
  dialog --backtitle "$(backtitle)" --title "Addons" \
      --infobox "Writing to user config" 0 0
  unset ADDONS
  declare -A ADDONS
  writeConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  for ADDON in ${resp}; do
    USERADDONS["${ADDON}"]=""
    writeConfigKey "addons.\"${ADDON}\"" "" "${USER_CONFIG_FILE}"
  done
  ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --title "Addons" \
    --msgbox "Loader Addons selected:\n${ADDONSINFO}" 0 0
}

###############################################################################
# Permit user select the modules to include
function modulesMenu() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  PLATFORM="$(readModelKey "${MODEL}" "platform")"
  KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
  if [ "${PLATFORM}" = "epyc7002" ]; then
    KVER="${PRODUCTVER}-${KVER}"
  fi
  dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
    --infobox "Reading modules" 0 0
  unset USERMODULES
  declare -A USERMODULES
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && USERMODULES["${KEY}"]="${VALUE}"
  done < <(readConfigMap "modules" "${USER_CONFIG_FILE}")
  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Show selected Modules" \
      2 "Select loaded Modules" \
      3 "Select all Modules" \
      4 "Deselect all Modules" \
      5 "Choose Modules to include" \
      6 "Add external module" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    case "$(<"${TMP_PATH}/resp")" in
      1)
        ITEMS=""
        for KEY in ${!USERMODULES[@]}; do
          ITEMS+="${KEY}: ${USERMODULES[$KEY]}\n"
        done
        dialog --backtitle "$(backtitle)" --title "User modules" \
          --msgbox "${ITEMS}" 0 0
        ;;
      2)
        dialog --backtitle "$(backtitle)" --colors --title "Modules" \
          --infobox "Selecting loaded modules" 0 0
        KOLIST=""
        for I in $(lsmod | awk -F' ' '{print $1}' | grep -v 'Module'); do
          KOLIST+="$(getdepends "${PLATFORM}" "${KVER}" "${I}") ${I} "
        done
        KOLIST=($(echo ${KOLIST} | tr ' ' '\n' | sort -u))
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${KOLIST[@]}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Selecting all modules" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        while read -r ID DESC; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done < <(getAllModules "${PLATFORM}" "${KVER}")
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Deselecting all modules" 0 0
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        rm -f "${TMP_PATH}/opts"
        while read -r ID DESC; do
          arrayExistItem "${ID}" "${!USERMODULES[@]}" && ACT="on" || ACT="off"
          echo "${ID} ${DESC} ${ACT}" >>"${TMP_PATH}/opts"
        done < <(getAllModules "${PLATFORM}" "${KVER}")
        dialog --backtitle "$(backtitle)" --title "Modules" --aspect 18 \
          --checklist "Select modules to include" 0 0 0 \
          --file "${TMP_PATH}/opts" 2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(<"${TMP_PATH}/resp")"
        dialog --backtitle "$(backtitle)" --title "Modules" \
           --infobox "Writing to user config" 0 0
        unset USERMODULES
        declare -A USERMODULES
        writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
        for ID in ${resp}; do
          USERMODULES["${ID}"]=""
          writeConfigKey "modules.\"${ID}\"" "" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        TEXT=""
        TEXT+="This function is experimental and dangerous. If you don't know much, please exit.\n"
        TEXT+="The imported .ko of this function will be implanted into the corresponding arch's modules package, which will affect all models of the arch.\n"
        TEXT+="This program will not determine the availability of imported modules or even make type judgments, as please double check if it is correct.\n"
        TEXT+="If you want to remove it, please go to the \"Update Menu\" -> \"Update modules\" to forcibly update the modules. All imports will be reset.\n"
        TEXT+="Do you want to continue?"
        dialog --backtitle "$(backtitle)" --title "Add external Module" \
            --yesno "${TEXT}" 0 0
        [ $? -ne 0 ] && continue
        dialog --backtitle "$(backtitle)" --aspect 18 --colors --inputbox "Please enter the complete URL to download.\n" 0 0 \
          2>"${TMP_PATH}/resp"
        URL="$(<"${TMP_PATH}/resp")"
        [ -z "${URL}" ] && continue
        clear
        echo "Downloading ${URL}"
        STATUS=$(curl -kLJO -w "%{http_code}" "${URL}" --progress-bar)
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Add external Module" --aspect 18 \
            --msgbox "ERROR: Check internet, URL or cache disk space" 0 0
          continue
        fi
        KONAME=$(basename "$URL")
        if [[ -n "${KONAME}" && "${KONAME##*.}" = "ko" ]]; then
          addToModules "${PLATFORM}" "${KVER}" "${TMP_UP_PATH}/${USER_FILE}"
          dialog --backtitle "$(backtitle)" --title "Add external Module" --aspect 18 \
            --msgbox "Module ${KONAME} added to ${PLATFORM}-${KVER}" 0 0
          rm -f "${KONAME}"
        else
          dialog --backtitle "$(backtitle)" --title "Add external Module" --aspect 18 \
            --msgbox "File format not recognized!" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
    esac
  done
}

###############################################################################
# Let user edit cmdline
function cmdlineMenu() {
  unset CMDLINE
  declare -A CMDLINE
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && CMDLINE["${KEY}"]="${VALUE}"
  done < <(readConfigMap "cmdline" "${USER_CONFIG_FILE}")
  echo "1 \"Add/edit a Cmdline item\""                          >"${TMP_PATH}/menu"
  echo "2 \"Delete Cmdline item(s)\""                           >>"${TMP_PATH}/menu"
  echo "3 \"CPU Fix\""                                          >>"${TMP_PATH}/menu"
  echo "4 \"RAM Fix\""                                          >>"${TMP_PATH}/menu"
  echo "5 \"PCI/IRQ Fix\""                                      >>"${TMP_PATH}/menu"
  echo "6 \"C-State Fix\""                                      >>"${TMP_PATH}/menu"
  echo "7 \"Show user Cmdline\""                                >>"${TMP_PATH}/menu"
  echo "8 \"Show Model/Build Cmdline\""                         >>"${TMP_PATH}/menu"
  echo "9 \"Kernelpanic Behavior\""                             >>"${TMP_PATH}/menu"
  # Loop menu
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "User cmdline" \
          --inputbox "Type a name of cmdline" 0 0 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        NAME="$(sed 's/://g' <"${TMP_PATH}/resp")"
        [ -z "${NAME//\"/}" ] && continue
        dialog --backtitle "$(backtitle)" --title "User cmdline" \
          --inputbox "Type a value of '${NAME}' cmdline" 0 0 "${CMDLINE[${NAME}]}" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        VALUE="$(<"${TMP_PATH}/resp")"
        CMDLINE[${NAME}]="${VALUE}"
        writeConfigKey "cmdline.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      2)
        if [ ${#CMDLINE[@]} -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --msgbox "No user cmdline to remove" 0 0
          continue
        fi
        ITEMS=""
        for I in "${!CMDLINE[@]}"; do
          [ -z "${CMDLINE[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${CMDLINE[${I}]} off "
        done
        dialog --backtitle "$(backtitle)" \
          --checklist "Select cmdline to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && continue
        for I in ${resp}; do
          unset 'CMDLINE[${I}]'
          deleteConfigKey "cmdline.\"${I}\"" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        dialog --clear --backtitle "$(backtitle)" \
          --title "CPU Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.nmi_watchdog" "0" "${USER_CONFIG_FILE}"
          writeConfigKey "cmdline.tsc" "reliable" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "CPU Fix" \
            --aspect 18 --msgbox "Fix installed to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.nmi_watchdog" "${USER_CONFIG_FILE}"
          deleteConfigKey "cmdline.tsc" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "CPU Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      4)
        dialog --clear --backtitle "$(backtitle)" \
          --title "RAM Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.disable_mtrr_trim" "0" "${USER_CONFIG_FILE}"
          writeConfigKey "cmdline.crashkernel" "auto" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "RAM Fix" \
            --aspect 18 --msgbox "Fix installed to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.disable_mtrr_trim" "${USER_CONFIG_FILE}"
          deleteConfigKey "cmdline.crashkernel" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "RAM Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      5)
        dialog --clear --backtitle "$(backtitle)" \
          --title "PCI/IRQ Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.pci" "routeirq" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
            --aspect 18 --msgbox "Fix installed to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.pci" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "PCI/IRQ Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      6)
        dialog --clear --backtitle "$(backtitle)" \
          --title "C-State Fix" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.intel_idle.max_cstate" "1" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "C-State Fix" \
            --aspect 18 --msgbox "Fix installed to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.intel_idle.max_cstate" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "C-State Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      7)
        dialog --clear --backtitle "$(backtitle)" \
          --title "i915 Patch" --menu "Fix?" 0 0 0 \
          1 "Install" \
          2 "Uninnstall" \
        2>"${TMP_PATH}/resp"
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && return 1
        if [ ${resp} -eq 1 ]; then
          writeConfigKey "cmdline.i915.enable_guc" "2" "${USER_CONFIG_FILE}"
          writeConfigKey "cmdline.i915.max_vfs" "7" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "C-State Fix" \
            --aspect 18 --msgbox "Fix installed to Cmdline" 0 0
        elif [ ${resp} -eq 2 ]; then
          deleteConfigKey "cmdline.i915.enable_guc" "${USER_CONFIG_FILE}"
          deleteConfigKey "cmdline.i915.max_vfs" "${USER_CONFIG_FILE}"
          dialog --backtitle "$(backtitle)" --title "C-State Fix" \
            --aspect 18 --msgbox "Fix uninstalled from Cmdline" 0 0
        fi
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      8)
        ITEMS=""
        for KEY in ${!CMDLINE[@]}; do
          ITEMS+="${KEY}: ${CMDLINE[$KEY]}\n"
        done
        dialog --backtitle "$(backtitle)" --title "User cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      9)
        ITEMS=""
        while IFS=': ' read -r KEY VALUE; do
          ITEMS+="${KEY}: ${VALUE}\n"
        done < <(readModelMap "${MODEL}" "productvers.[${PRODUCTVER}].cmdline")
        dialog --backtitle "$(backtitle)" --title "Model/Version cmdline" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
      0)
        rm -f "${TMP_PATH}/opts"
        echo "5 \"Reboot after 5 seconds\"" >>"${TMP_PATH}/opts"
        echo "0 \"No reboot\"" >>"${TMP_PATH}/opts"
        echo "-1 \"Restart immediately\"" >>"${TMP_PATH}/opts"
        dialog --backtitle "$(backtitle)" --colors --title "Kernelpanic" \
          --default-item "${KERNELPANIC}" --menu "Choose a time(seconds)" 0 0 0 --file "${TMP_PATH}/opts" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        resp=$(cat ${TMP_PATH}/resp 2>/dev/null)
        [ -z "${resp}" ] && return
        KERNELPANIC=${resp}
        writeConfigKey "arc.kernelpanic" "${KERNELPANIC}" "${USER_CONFIG_FILE}"
        ;;
    esac
  done
}

###############################################################################
# let user configure synoinfo entries
function synoinfoMenu() {
  # read synoinfo from user config
  unset SYNOINFO
  declare -A SYNOINFO
  while IFS=': ' read -r KEY VALUE; do
    [ -n "${KEY}" ] && SYNOINFO["${KEY}"]="${VALUE}"
  done < <(readConfigMap "synoinfo" "${USER_CONFIG_FILE}")

  echo "1 \"Add/edit Synoinfo item\""     >"${TMP_PATH}/menu"
  echo "2 \"Delete Synoinfo item(s)\""    >>"${TMP_PATH}/menu"
  echo "3 \"Show Synoinfo entries\""      >>"${TMP_PATH}/menu"

  # menu loop
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      --file "${TMP_PATH}/menu" 2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --inputbox "Type a name of synoinfo entry" 0 0 \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        NAME="$(<"${TMP_PATH}/resp")"
        [ -z "${NAME//\"/}" ] && continue
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --inputbox "Type a value of '${NAME}' entry" 0 0 "${SYNOINFO[${NAME}]}" \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        VALUE="$(<"${TMP_PATH}/resp")"
        SYNOINFO[${NAME}]="${VALUE}"
        writeConfigKey "synoinfo.\"${NAME//\"/}\"" "${VALUE}" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      2)
        if [ ${#SYNOINFO[@]} -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --msgbox "No synoinfo entries to remove" 0 0
          continue
        fi
        ITEMS=""
        for I in "${!SYNOINFO[@]}"; do
          [ -z "${SYNOINFO[${I}]}" ] && ITEMS+="${I} \"\" off " || ITEMS+="${I} ${SYNOINFO[${I}]} off "
        done
        dialog --backtitle "$(backtitle)" \
          --checklist "Select synoinfo entry to remove" 0 0 0 ${ITEMS} \
          2>"${TMP_PATH}/resp"
        [ $? -ne 0 ] && continue
        resp="$(<"${TMP_PATH}/resp")"
        [ -z "${resp}" ] && continue
        for I in ${resp}; do
          unset 'SYNOINFO[${I}]'
          deleteConfigKey "synoinfo.\"${I}\"" "${USER_CONFIG_FILE}"
        done
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        ;;
      3)
        ITEMS=""
        for KEY in ${!SYNOINFO[@]}; do
          ITEMS+="${KEY}: ${SYNOINFO[$KEY]}\n"
        done
        dialog --backtitle "$(backtitle)" --title "Synoinfo entries" \
          --aspect 18 --msgbox "${ITEMS}" 0 0
        ;;
    esac
  done
}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "$(backtitle)" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a Layout" 0 0 0 "azerty" "bepo" "carpalx" "colemak" \
    "dvorak" "fgGIod" "neo" "olpc" "qwerty" "qwertz" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return 1
  LAYOUT="$(<"${TMP_PATH}/resp")"
  OPTIONS=""
  while read -r KM; do
    OPTIONS+="${KM::-7} "
  done < <(cd /usr/share/keymaps/i386/${LAYOUT}; ls *.map.gz)
  dialog --backtitle "$(backtitle)" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && continue
  resp="$(<"${TMP_PATH}/resp")"
  [ -z "${resp}" ] && continue
  KEYMAP=${resp}
  writeConfigKey "layout" "${LAYOUT}" "${USER_CONFIG_FILE}"
  writeConfigKey "keymap" "${KEYMAP}" "${USER_CONFIG_FILE}"
  loadkeys /usr/share/keymaps/i386/${LAYOUT}/${KEYMAP}.map.gz
}

###############################################################################
# Shows usb menu to user
function usbMenu() {
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Mount USB as Internal" \
      2 "Mount USB as Normal" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        writeConfigKey "synoinfo.maxdisks" "24" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.usbportcfg" "0" "${USER_CONFIG_FILE}"
        writeConfigKey "synoinfo.internalportcfg" "0xffffffff" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.usbmount" "true" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Mount USB as Internal" \
          --aspect 18 --msgbox "Mount USB as Internal - successful!" 0 0
        ;;
      2)
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        deleteConfigKey "synoinfo.maxdisks" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.usbportcfg" "${USER_CONFIG_FILE}"
        deleteConfigKey "synoinfo.internalportcfg" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Mount USB as Normal" \
          --aspect 18 --msgbox "Mount USB as Normal - successful!" 0 0
        ;;
    esac
  else
    return 1
  fi
}

###############################################################################
# Shows backup menu to user
function backupMenu() {
  NEXT="1"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${BUILDDONE}" = "true" ]; then
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Backup Config with Code" \
        2 "Restore Config with Code" \
        3 "Recover from DSM" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      case "$(<"${TMP_PATH}/resp")" in
        1)
          dialog --backtitle "$(backtitle)" --title "Backup Config with Code" \
              --infobox "Write down your Code for Restore!" 0 0
          if [ -f "${USER_CONFIG_FILE}" ]; then
            GENHASH="$(cat "${USER_CONFIG_FILE}" | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)"
            dialog --backtitle "$(backtitle)" --title "Backup Config with Code" --msgbox "Your Code: ${GENHASH}" 0 0
          else
            dialog --backtitle "$(backtitle)" --title "Backup Config with Code" --msgbox "No Config for Backup found!" 0 0
          fi
          ;;
        2)
          while true; do
            dialog --backtitle "$(backtitle)" --title "Restore with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>"${TMP_PATH}/resp"
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="$(<"${TMP_PATH}/resp")"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "$(backtitle)" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          rm -f "${BACKUPDIR}/user-config.yml"
          curl -k https://dpaste.com/${GENHASH}.txt >"${BACKUPDIR}/user-config.yml"
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            CONFIG_VERSION="$(readConfigKey "arc.version" "${BACKUPDIR}/user-config.yml")"
            if [ "${ARC_VERSION}" = "${CONFIG_VERSION}" ]; then
              # Copy config back to location
              cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
              dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
                --msgbox "Restore complete!" 0 0
            else
              cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
              dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
                --msgbox "Version mismatch!\nIt is possible that your Config will not work!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
            return 1
          fi
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          arcbuild
          ;;
        3)
          dialog --backtitle "$(backtitle)" --title "Try to recover DSM" --aspect 18 \
            --infobox "Trying to recover a DSM installed system" 0 0
          if findAndMountDSMRoot; then
            MODEL=""
            PRODUCTVER=""
            if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep majorversion)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep minorversion)
              if [ -n "${unique}" ] ; then
                while read -r F; do
                  M="$(basename ${F})"
                  M="${M::-4}"
                  UNIQUE="$(readModelKey "${M}" "unique")"
                  [ "${unique}" = "${UNIQUE}" ] || continue
                  # Found
                  writeConfigKey "model" "${M}" "${USER_CONFIG_FILE}"
                done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
                MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
                if [ -n "${MODEL}" ]; then
                  writeConfigKey "productver" "${majorversion}.${minorversion}" "${USER_CONFIG_FILE}"
                  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
                  if [ -n "${PRODUCTVER}" ]; then
                    cp -f "${DSMROOT_PATH}/.syno/patch/zImage" "${PART2_PATH}"
                    cp -f "${DSMROOT_PATH}/.syno/patch/rd.gz" "${PART2_PATH}"
                    TEXT="Installation found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
                    SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
                    if [ -n "${SN}" ]; then
                      deleteConfigKey "arc.patch" "${USER_CONFIG_FILE}"
                      SNARC="$(readConfigKey "arc.serial" "${MODEL_CONFIG_PATH}/${MODEL}.yml")"
                      writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
                      TEXT+="\nSerial: ${SN}"
                      if [ "${SN}" = "${SNARC}" ]; then
                        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
                      else
                        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
                      fi
                      ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
                      TEXT+="\nArc Patch: ${ARCPATCH}"
                    fi
                    dialog --backtitle "$(backtitle)" --title "Try to recover DSM" \
                      --aspect 18 --msgbox "${TEXT}" 0 0
                    ARCRECOVERY="true"
                    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
                    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
                    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
                    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
                    arcbuild
                  fi
                fi
              fi
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Try recovery DSM" --aspect 18 \
              --msgbox "Unfortunately Arc couldn't mount the DSM partition!" 0 0
          fi
          ;;
      esac
    done
  else
    while true; do
      dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
        1 "Restore Config with Code" \
        2 "Recover from DSM" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      case "$(<"${TMP_PATH}/resp")" in
        1)
          while true; do
            dialog --backtitle "$(backtitle)" --title "Restore with Code" \
              --inputbox "Type your Code here!" 0 0 \
              2>"${TMP_PATH}/resp"
            RET=$?
            [ ${RET} -ne 0 ] && break 2
            GENHASH="$(<"${TMP_PATH}/resp")"
            [ ${#GENHASH} -eq 9 ] && break
            dialog --backtitle "$(backtitle)" --title "Restore with Code" --msgbox "Invalid Code" 0 0
          done
          rm -f "${BACKUPDIR}/user-config.yml"
          curl -k https://dpaste.com/${GENHASH}.txt >"${BACKUPDIR}/user-config.yml"
          if [ -f "${BACKUPDIR}/user-config.yml" ]; then
            CONFIG_VERSION="$(readConfigKey "arc.version" "${BACKUPDIR}/user-config.yml")"
            if [ "${ARC_VERSION}" = "${CONFIG_VERSION}" ]; then
              # Copy config back to location
              cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
              dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
                --msgbox "Restore complete!" 0 0
            else
              cp -f "${BACKUPDIR}/user-config.yml" "${USER_CONFIG_FILE}"
              dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
                --msgbox "Version mismatch!\nIt is possible that your Config will not work!" 0 0
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Restore Config" --aspect 18 \
              --msgbox "No Config Backup found" 0 0
            return 1
          fi
          MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
          PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
          ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
          ARCRECOVERY="true"
          ONLYVERSION="true"
          CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
          writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
          BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
          arcbuild
          ;;
        2)
          dialog --backtitle "$(backtitle)" --title "Try to recover DSM" --aspect 18 \
            --infobox "Trying to recover a DSM installed system" 0 0
          if findAndMountDSMRoot; then
            MODEL=""
            PRODUCTVER=""
            if [ -f "${DSMROOT_PATH}/.syno/patch/VERSION" ]; then
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep unique)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep majorversion)
              eval $(cat ${DSMROOT_PATH}/.syno/patch/VERSION | grep minorversion)
              if [ -n "${unique}" ] ; then
                while read -r F; do
                  M="$(basename ${F})"
                  M="${M::-4}"
                  UNIQUE="$(readModelKey "${M}" "unique")"
                  [ "${unique}" = "${UNIQUE}" ] || continue
                  # Found
                  writeConfigKey "model" "${M}" "${USER_CONFIG_FILE}"
                done < <(find "${MODEL_CONFIG_PATH}" -maxdepth 1 -name \*.yml | sort)
                MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
                if [ -n "${MODEL}" ]; then
                  writeConfigKey "productver" "${majorversion}.${minorversion}" "${USER_CONFIG_FILE}"
                  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
                  if [ -n "${PRODUCTVER}" ]; then
                    cp -f "${DSMROOT_PATH}/.syno/patch/zImage" "${PART2_PATH}"
                    cp -f "${DSMROOT_PATH}/.syno/patch/rd.gz" "${PART2_PATH}"
                    TEXT="Installation found:\nModel: ${MODEL}\nVersion: ${PRODUCTVER}"
                    SN=$(_get_conf_kv SN "${DSMROOT_PATH}/etc/synoinfo.conf")
                    if [ -n "${SN}" ]; then
                      deleteConfigKey "arc.patch" "${USER_CONFIG_FILE}"
                      SNARC="$(readConfigKey "arc.serial" "${MODEL_CONFIG_PATH}/${MODEL}.yml")"
                      writeConfigKey "arc.sn" "${SN}" "${USER_CONFIG_FILE}"
                      TEXT+="\nSerial: ${SN}"
                      if [ "${SN}" = "${SNARC}" ]; then
                        writeConfigKey "arc.patch" "true" "${USER_CONFIG_FILE}"
                      else
                        writeConfigKey "arc.patch" "false" "${USER_CONFIG_FILE}"
                      fi
                      ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
                      TEXT+="\nArc Patch: ${ARCPATCH}"
                    fi
                    dialog --backtitle "$(backtitle)" --title "Try to recover DSM" \
                      --aspect 18 --msgbox "${TEXT}" 0 0
                    ARCRECOVERY="true"
                    writeConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
                    CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
                    writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
                    BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
                    arcbuild
                  fi
                fi
              fi
            fi
          else
            dialog --backtitle "$(backtitle)" --title "Try recovery DSM" --aspect 18 \
              --msgbox "Unfortunately Arc couldn't mount the DSM partition!" 0 0
          fi
          ;;
      esac
    done
  fi
}

###############################################################################
# Shows update menu to user
function updateMenu() {
  NEXT="1"
  while true; do
    dialog --backtitle "$(backtitle)" --menu "Choose an Option" 0 0 0 \
      1 "Full-Upgrade Loader" \
      2 "Update Loader" \
      3 "Update Addons" \
      4 "Update Patches" \
      5 "Update Modules" \
      6 "Update Configs" \
      7 "Update LKMs" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && return 1
    case "$(<"${TMP_PATH}/resp")" in
      1)
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Checking latest version..." 0 0
        ACTUALVERSION="${ARC_VERSION}"
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
              --msgbox "Error checking new version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        if [ "${ACTUALVERSION}" = "${TAG}" ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
            --yesno "No new version. Actual version is ${ACTUALVERSION}\nForce update?" 0 0
          [ $? -ne 0 ] && continue
        fi
        # Download update file
        STATUS=$(curl --insecure -w "%{http_code}" -L "https://github.com/AuxXxilium/arc/releases/download/${TAG}/arc-${TAG}.img.zip" -o "${TMP_PATH}/arc-${TAG}.img.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
            --msgbox "Error downloading update file" 0 0
          return 1
        fi
        unzip -oq "${TMP_PATH}/arc-${TAG}.img.zip" -d "${TMP_PATH}"
        rm -f "${TMP_PATH}/arc-${TAG}.img.zip"
        if [ $? -ne 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
            --msgbox "Error extracting update file" 0 0
          return 1
        fi
        if [[ -f "${USER_CONFIG_FILE}" && "${CONFDONE}" = "true" ]]; then
          GENHASH="$(cat "${USER_CONFIG_FILE}" | curl -s -F "content=<-" http://dpaste.com/api/v2/ | cut -c 19-)"
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --msgbox "Backup config successful!\nWrite down your Code: ${GENHASH}\n\nAfter Reboot use: Restore with Code." 0 0
        else
          dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --msgbox "No config for Backup found!" 0 0
        fi
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --infobox "Installing new Loader Image" 0 0
        # Process complete update
        umount "${PART1_PATH}" "${PART2_PATH}" "${PART3_PATH}"
        dd if="${TMP_PATH}/arc.img" of=$(blkid | grep 'LABEL="ARC3"' | cut -d3 -f1) bs=1M conv=fsync
        # Ask for Boot
        rm -f "${TMP_PATH}/arc.img"
        dialog --backtitle "$(backtitle)" --title "Upgrade Loader" --aspect 18 \
          --yesno "Arc Upgrade successful. New Version: ${TAG}\nReboot?" 0 0
        [ $? -ne 0 ] && continue
        exec reboot
        exit 0
        ;;
      2)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Loader" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && continue
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
              --msgbox "Error checking new version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Loader" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc/releases/download/${TAG}/update.zip" -o "${TMP_PATH}/update.zip")
        if [ $? -ne 0 ] || [ ${STATUS} -ne 200 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
            --msgbox "Error downloading!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --infobox "Extracting" 0 0
        [ -f "${TMP_PATH}/update" ] && rm -rf "${TMP_PATH}/update"
        mkdir -p "${TMP_PATH}/update"
        unzip -oq "${TMP_PATH}/update.zip" -d "${TMP_PATH}/update" >/dev/null 2>&1
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --infobox "Updating Loader Image" 0 0
        cp -f "${TMP_PATH}/update/bzImage" "${PART3_PATH}/bzImage-arc"
        cp -f "${TMP_PATH}/update/rootfs.cpio.xz" "${PART3_PATH}/initrd-arc"
        cp -f "${TMP_PATH}/update/ARC-VERSION" "${PART1_PATH}/ARC-VERSION"
        cp -f "${TMP_PATH}/update/grub.cfg" "${PART1_PATH}/boot/grub/grub.cfg"
        rm -rf "${TMP_PATH}/update" 
        rm -f "${TMP_PATH}/update.zip"
        dialog --backtitle "$(backtitle)" --title "Update Loader" --aspect 18 \
          --yesno "Arc updated successful. New Version: ${TAG}\nReboot?" 0 0
        [ $? -ne 0 ] && continue
        exec reboot
        exit 0
        ;;
      3)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Addons" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        [ $? -ne 0 ] && continue
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-addons/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Addons" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-addons/releases/download/${TAG}/addons.zip" -o "${TMP_PATH}/addons.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
            --msgbox "Error downloading!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${ADDONS_PATH}"
        mkdir -p "${ADDONS_PATH}"
        unzip -oq "${TMP_PATH}/addons.zip" -d "${ADDONS_PATH}" >/dev/null 2>&1
        dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
          --infobox "Installing new Addons" 0 0
        for PKG in $(ls ${ADDONS_PATH}/*.addon); do
          ADDON=$(basename ${PKG} | sed 's|.addon||')
          rm -rf "${ADDONS_PATH}/${ADDON}"
          mkdir -p "${ADDONS_PATH}/${ADDON}"
          tar -xaf "${PKG}" -C "${ADDONS_PATH}/${ADDON}" >/dev/null 2>&1
          rm -f "${ADDONS_PATH}/${ADDON}.addon"
        done
        rm -f "${TMP_PATH}/addons.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Addons" --aspect 18 \
          --msgbox "Addons updated successful! New Version: ${TAG}" 0 0
        ;;
      4)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Patches" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-patches/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Patches" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-patches/releases/download/${TAG}/patches.zip" -o "${TMP_PATH}/patches.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
            --msgbox "Error downloading!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${PATCH_PATH}"
        mkdir -p "${PATCH_PATH}"
        unzip -oq "${TMP_PATH}/patches.zip" -d "${PATCH_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/patches.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Patches" --aspect 18 \
          --msgbox "Patches updated successful! New Version: ${TAG}" 0 0
        ;;
      5)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Modules" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-modules/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl -k -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-modules/releases/download/${TAG}/modules.zip" -o "${TMP_PATH}/modules.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
            --msgbox "Error downloading!" 0 0
          return 1
        fi
        MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
        PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
        if [[ -n "${MODEL}" && -n "${PRODUCTVER}" ]]; then
          PLATFORM="$(readModelKey "${MODEL}" "platform")"
          KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
          if [ "${PLATFORM}" = "epyc7002" ]; then
            KVER="${PRODUCTVER}-${KVER}"
          fi
        fi
        rm -rf "${MODULES_PATH}"
        mkdir -p "${MODULES_PATH}"
        unzip -oq "${TMP_PATH}/modules.zip" -d "${MODULES_PATH}" >/dev/null 2>&1
        # Rebuild modules if model/build is selected
        if [[ -n "${PLATFORM}" && -n "${KVER}" ]]; then
          writeConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
          while read -r ID DESC; do
            writeConfigKey "modules.${ID}" "" "${USER_CONFIG_FILE}"
          done < <(getAllModules "${PLATFORM}" "${KVER}")
        fi
        rm -f "${TMP_PATH}/modules.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Modules" --aspect 18 \
          --msgbox "Modules updated successful. New Version: ${TAG}" 0 0
        ;;
      6)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update Configs" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/arc-configs/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/arc-configs/releases/download/${TAG}/configs.zip" -o "${TMP_PATH}/configs.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
            --msgbox "Error downloading!" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${MODEL_CONFIG_PATH}"
        mkdir -p "${MODEL_CONFIG_PATH}"
        unzip -oq "${TMP_PATH}/configs.zip" -d "${MODEL_CONFIG_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/configs.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update Configs" --aspect 18 \
          --msgbox "Configs updated successful! New Version: ${TAG}" 0 0
        ;;
      7)
        # Ask for Tag
        dialog --clear --backtitle "$(backtitle)" --title "Update LKMs" \
          --menu "Which Version?" 0 0 0 \
          1 "Latest" \
          2 "Select Version" \
        2>"${TMP_PATH}/opts"
        opts="$(<"${TMP_PATH}/opts")"
        [ -z "${opts}" ] && return 1
        if [ ${opts} -eq 1 ]; then
          TAG="$(curl --insecure -s https://api.github.com/repos/AuxXxilium/redpill-lkm/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')"
          if [[ $? -ne 0 || -z "${TAG}" ]]; then
            dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
              --msgbox "Error checking new Version!" 0 0
            return 1
          fi
        elif [ ${opts} -eq 2 ]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" \
          --inputbox "Type the Version!" 0 0 \
          2>"${TMP_PATH}/input"
          TAG="$(<"${TMP_PATH}/input")"
          [ -z "${TAG}" ] && continue
        fi
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Downloading ${TAG}" 0 0
        STATUS=$(curl --insecure -s -w "%{http_code}" -L "https://github.com/AuxXxilium/redpill-lkm/releases/download/${TAG}/rp-lkms.zip" -o "${TMP_PATH}/rp-lkms.zip")
        if [[ $? -ne 0 || ${STATUS} -ne 200 ]]; then
          dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
            --msgbox "Error downloading" 0 0
          return 1
        fi
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --infobox "Extracting" 0 0
        rm -rf "${LKM_PATH}"
        mkdir -p "${LKM_PATH}"
        unzip -oq "${TMP_PATH}/rp-lkms.zip" -d "${LKM_PATH}" >/dev/null 2>&1
        rm -f "${TMP_PATH}/rp-lkms.zip"
        writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
        BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
        dialog --backtitle "$(backtitle)" --title "Update LKMs" --aspect 18 \
          --msgbox "LKMs updated successful! New Version: ${TAG}" 0 0
        ;;
    esac
  done
}

###############################################################################
# Show Storagemenu to user
function storageMenu() {
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  DT="$(readModelKey "${MODEL}" "dt")"
  # Get Portmap for Loader
  getmap
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Show Storagemenu to user
function networkMenu() {
  # Get Network Config for Loader
  getnet
  writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
}

###############################################################################
# Shows Systeminfo to user
function sysinfo() {
  # Checks for Systeminfo Menu
  CPUINFO="$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')"
  # Check if machine has EFI
  [ -d /sys/firmware/efi ] && BOOTSYS="EFI" || BOOTSYS="Legacy"
  VENDOR="$(dmidecode -s system-product-name)"
  BOARD="$(dmidecode -s baseboard-product-name)"
  ETHX=$(ls /sys/class/net/ | grep -v lo || true)
  NIC="$(readConfigKey "device.nic" "${USER_CONFIG_FILE}")"
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  if [ "${CONFDONE}" = "true" ]; then
    MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
    PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    DT="$(readModelKey "${MODEL}" "dt")"
    KVER="$(readModelKey "${MODEL}" "productvers.[${PRODUCTVER}].kver")"
    ARCPATCH="$(readConfigKey "arc.patch" "${USER_CONFIG_FILE}")"
    ADDONSINFO="$(readConfigEntriesArray "addons" "${USER_CONFIG_FILE}")"
    REMAP="$(readConfigKey "arc.remap" "${USER_CONFIG_FILE}")"
    if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
      PORTMAP="$(readConfigKey "cmdline.SataPortMap" "${USER_CONFIG_FILE}")"
      DISKMAP="$(readConfigKey "cmdline.DiskIdxMap" "${USER_CONFIG_FILE}")"
    elif [ "${REMAP}" = "remap" ]; then
      PORTMAP="$(readConfigKey "cmdline.sata_remap" "${USER_CONFIG_FILE}")"
    fi
  fi
  DIRECTBOOT="$(readConfigKey "arc.directboot" "${USER_CONFIG_FILE}")"
  BOOTCOUNT="$(readConfigKey "arc.bootcount" "${USER_CONFIG_FILE}")"
  USBMOUNT="$(readConfigKey "arc.usbmount" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  KERNELLOAD="$(readConfigKey "arc.kernelload" "${USER_CONFIG_FILE}")"
  MACSYS="$(readConfigKey "arc.macsys" "${USER_CONFIG_FILE}")"
  HDDSORT="$(readConfigKey "arc.hddsort" "${USER_CONFIG_FILE}")"
  MODULESINFO="$(lsmod | awk -F' ' '{print $1}' | grep -v 'Module')"
  MODULESVERSION="$(cat "${MODULES_PATH}/VERSION")"
  ADDONSVERSION="$(cat "${ADDONS_PATH}/VERSION")"
  LKMVERSION="$(cat "${LKM_PATH}/VERSION")"
  CONFIGSVERSION="$(cat "${MODEL_CONFIG_PATH}/VERSION")"
  PATCHESVERSION="$(cat "${PATCH_PATH}/VERSION")"
  TEXT=""
  # Print System Informations
  TEXT+="\n\Z4> System: ${MACHINE} | ${BOOTSYS}\Zn"
  TEXT+="\n  Vendor | Board: \Zb${VENDOR} | ${BOARD}\Zn"
  TEXT+="\n  CPU: \Zb${CPUINFO}\Zn"
  TEXT+="\n  Memory: \Zb$((${RAMTOTAL} / 1024))GB\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4> Network: ${NIC} NIC\Zn"
  for N in ${ETHX}; do
    DRIVER=$(ls -ld /sys/class/net/${N}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
    MAC="$(cat /sys/class/net/${N}/address | sed 's/://g')"
    while true; do
      if ethtool ${N} | grep 'Link detected' | grep -q 'no'; then
        TEXT+="\n  ${DRIVER}: \ZbIP: NOT CONNECTED | MAC: ${MAC}\Zn"
        break
      fi
      NETIP="$(getIP)"
      if [ "${STATICIP}" = "true" ]; then
        ARCIP="$(readConfigKey "arc.ip" "${USER_CONFIG_FILE}")"
        if [[ "${N}" = "eth0" && -n "${ARCIP}" ]]; then
          NETIP="${ARCIP}"
          MSG="STATIC"
        else
          MSG="DHCP"
        fi
      else
        MSG="DHCP"
      fi
      if [ -n "${NETIP}" ]; then
        SPEED=$(ethtool ${N} | grep "Speed:" | awk '{print $2}')
        TEXT+="\n  ${DRIVER} (${SPEED} | ${MSG}) \ZbIP: ${NETIP} | Mac: ${MAC}\Zn"
        break
      fi
      COUNT=$((${COUNT} + 1))
      if [ ${COUNT} -eq 3 ]; then
        TEXT+="\n  ${DRIVER}: \ZbIP: TIMEOUT | MAC: ${MAC}\Zn"
        break
      fi
      sleep 1
    done
  done
  # Print Config Informations
  TEXT+="\n"
  TEXT+="\n\Z4> Arc: ${ARC_VERSION}\Zn"
  TEXT+="\n  Subversion Loader: \ZbAddons ${ADDONSVERSION} | Configs ${CONFIGSVERSION} | Patches ${PATCHESVERSION}\Zn"
  TEXT+="\n  Subversion DSM: \ZbModules ${MODULESVERSION} | LKM ${LKMVERSION}\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> DSM ${PRODUCTVER}: ${MODEL}\Zn"
  TEXT+="\n   Kernel | LKM: \Zb${KVER} | ${LKM}\Zn"
  TEXT+="\n   Platform | DeviceTree: \Zb${PLATFORM} | ${DT}\Zn"
  TEXT+="\n\Z4>> Loader\Zn"
  TEXT+="\n   Arc Settings | Kernelload: \Zb${ARCPATCH} | ${KERNELLOAD}\Zn"
  TEXT+="\n   Directboot: \Zb${DIRECTBOOT}\Zn"
  TEXT+="\n   Config | Build: \Zb${CONFDONE} | ${BUILDDONE}\Zn"
  TEXT+="\n   MacSys: \Zb${MACSYS}\Zn"
  TEXT+="\n   Bootcount: \Zb${BOOTCOUNT}\Zn"
  TEXT+="\n\Z4>> Addons | Modules\Zn"
  TEXT+="\n   Addons selected: \Zb${ADDONSINFO}\Zn"
  TEXT+="\n   Modules loaded: \Zb${MODULESINFO}\Zn"
  TEXT+="\n\Z4>> Settings\Zn"
  TEXT+="\n   Static IP: \Zb${STATICIP}\Zn"
  TEXT+="\n   Sort Drives: \Zb${HDDSORT}\Zn"
  if [[ "${REMAP}" = "acports" || "${REMAP}" = "maxports" ]]; then
    TEXT+="\n   SataPortMap | DiskIdxMap: \Zb${PORTMAP} | ${DISKMAP}\Zn"
  elif [ "${REMAP}" = "remap" ]; then
    TEXT+="\n   SataRemap: \Zb${PORTMAP}\Zn"
  elif [ "${REMAP}" = "user" ]; then
    TEXT+="\n   PortMap: \Zb"User"\Zn"
  fi
  if [ "${PLATFORM}" = "broadwellnk" ]; then
    TEXT+="\n   USB Mount: \Zb${USBMOUNT}\Zn"
  fi
  TEXT+="\n"
  # Check for Controller // 104=RAID // 106=SATA // 107=SAS
  TEXT+="\n\Z4> Storage\Zn"
  # Get Information for Sata Controller
  NUMPORTS=0
  if [ $(lspci -d ::106 | wc -l) -gt 0 ]; then
    TEXT+="\n  SATA Controller:\n"
    for PCI in $(lspci -d ::106 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      TEXT+="\Zb  ${NAME}\Zn\n  Ports: "
      PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      for P in ${PORTS}; do
        if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
          DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ] && echo 1 || echo 2)"
          if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ]; then
            TEXT+="\Z1\Zb$(printf "%02d" ${P})\Zn "
          else
            TEXT+="\Z2\Zb$(printf "%02d" ${P})\Zn "
            NUMPORTS=$((${NUMPORTS} + 1))
          fi
        else
          TEXT+="\Zb$(printf "%02d" ${P})\Zn "
        fi
      done
      TEXT+="\n  Ports with color \Z1\Zbred\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected.\n"
    done
  fi
  if [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    TEXT+="\n  SAS Controller:\n"
    for PCI in $(lspci -d ::107 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::104 | wc -l) -gt 0 ]; then
    TEXT+="\n  SCSI Controller:\n"
    for PCI in $(lspci -d ::104 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/scsi_host" && $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ]]; then
    TEXT+="\n USB Controller:\n"
    for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [[ -d "/sys/class/mmc_host" && $(ls -l /sys/class/mmc_host | grep mmc_host | wc -l) -gt 0 ]]; then
    TEXT+="\n MMC Controller:\n"
    for PCI in $(lspci -d ::805 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORTNUM=$(ls -l /sys/class/mmc_host | grep "${PCI}" | wc -l)
      PORTNUM=$(ls -l /sys/block/mmc* | grep "${PCI}" | wc -l)
      [ ${PORTNUM} -eq 0 ] && continue
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  if [ $(lspci -d ::108 | wc -l) -gt 0 ]; then
    TEXT+="\n NVMe Controller:\n"
    for PCI in $(lspci -d ::108 | awk '{print $1}'); do
      NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
      PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
      PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
      TEXT+="\Zb  ${NAME}\Zn\n  Drives: ${PORTNUM}\n"
      NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
    done
  fi
  TEXT+="\n  Drives total: \Zb${NUMPORTS}\Zn"
  dialog --backtitle "$(backtitle)" --colors --title "Sysinfo" \
    --msgbox "${TEXT}" 0 0
}

###############################################################################
# Shows Systeminfo to user
function credits() {
  # Print Credits Informations
  TEXT=""
  TEXT+="\n\Z4> Arc Loader:\Zn"
  TEXT+="\n  Github: \Zbhttps://github.com/AuxXxilium\Zn"
  TEXT+="\n  Website: \Zbhttps://auxxxilium.tech\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Developer:\Zn"
  TEXT+="\n   Arc Loader: \ZbAuxXxilium\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Based on:\Zn"
  TEXT+="\n   Redpill: \ZbTTG / Pocopico\Zn"
  TEXT+="\n   ARPL: \Zbfbelavenuto / wjz304\Zn"
  TEXT+="\n   CPU Info: \ZbFOXBI\Zn"
  TEXT+="\n   System: \ZbBuildroot 2023.02.x\Zn"
  TEXT+="\n"
  TEXT+="\n\Z4>> Note:\Zn"
  TEXT+="\n   Arc and all Parts are OpenSource."
  TEXT+="\n   Commercial use is not permitted!"
  TEXT+="\n   This Loader is FREE and it is forbidden"
  TEXT+="\n   to sell Arc or Parts of this."
  TEXT+="\n"
  dialog --backtitle "$(backtitle)" --colors --title "Credits" \
    --msgbox "${TEXT}" 0 0
}

###############################################################################
# allow setting Static IP for DSM
function staticIPMenu() {
  mkdir -p "${TMP_PATH}/sdX1"
  for I in $(ls /dev/sd.*1 2>/dev/null | grep -v "${LOADER_DISK}1"); do
    mount "${I}" "${TMP_PATH}/sdX1"
    [ -f "${TMP_PATH}/sdX1/etc/sysconfig/network-scripts/ifcfg-eth0" ] && . "${TMP_PATH}/sdX1/etc/sysconfig/network-scripts/ifcfg-eth0"
    umount "${I}"
    break
  done
  rm -rf "${TMP_PATH}/sdX1"
  TEXT=""
  TEXT+="This feature will allow you to set a static IP for eth0.\n"
  TEXT+="Actual Settings are:\n"
  TEXT+="Mode: ${BOOTPROTO}\n"
  if [ "${BOOTPROTO}" = "static" ]; then
    TEXT+="IP: ${IPADDR}\n"
    TEXT+="NETMASK: ${NETMASK}\n"
  fi
  TEXT+="Do you want to change Config?"
  dialog --backtitle "$(backtitle)" --title "DHCP/Static IP" \
      --yesno "${TEXT}" 0 0
  [ $? -ne 0 ] && return 1
  dialog --clear --backtitle "$(backtitle)" --title "DHCP/Static IP" \
    --menu "DHCP or STATIC?" 0 0 0 \
      1 "DHCP" \
      2 "STATIC" \
    2>"${TMP_PATH}/opts"
    opts="$(<"${TMP_PATH}/opts")"
    [ -z "${opts}" ] && return 1
    if [ ${opts} -eq 1 ]; then
      echo -e "DEVICE=eth0\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=off" >"${TMP_PATH}/ifcfg-eth0"
    elif [ ${opts} -eq 2 ]; then
      dialog --backtitle "$(backtitle)" --title "DHCP/Static IP" \
        --inputbox "Type a Static IP\nEq: 192.168.0.1" 0 0 "${IPADDR}" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      IPADDR="$(<"${TMP_PATH}/resp")"
      dialog --backtitle "$(backtitle)" --title "DHCP/Static IP" \
        --inputbox "Type a Netmask\nEq: 255.255.255.0" 0 0 "${NETMASK}" \
        2>"${TMP_PATH}/resp"
      [ $? -ne 0 ] && return 1
      NETMASK="$(<"${TMP_PATH}/resp")"
      echo -e "DEVICE=eth0\nBOOTPROTO=static\nONBOOT=yes\nIPV6INIT=off\nIPADDR=${IPADDR}\nNETMASK=${NETMASK}" >"${TMP_PATH}/ifcfg-eth0"
    fi
    dialog --backtitle "$(backtitle)" --title "DHCP/Static IP" \
      --yesno "Do you want to set this Config?" 0 0
    [ $? -ne 0 ] && return 1
    (
      mkdir -p "${TMP_PATH}/sdX1"
      for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
        mount "${I}" "${TMP_PATH}/sdX1"
        [ -f "${TMP_PATH}/sdX1/etc/sysconfig/network-scripts/ifcfg-eth0" ] && cp -f "${TMP_PATH}/ifcfg-eth0" "${TMP_PATH}/sdX1/etc/sysconfig/network-scripts/ifcfg-eth0"
        sync
        umount "${I}"
      done
      rm -rf "${TMP_PATH}/sdX1"
    )
    if [[ -n "${IPADDR}" && -n "${NETMASK}" ]]; then
      NETMASK=$(convert_netmask "${NETMASK}")
      ip addr add ${IPADDR}/${NETMASK} dev eth0
      writeConfigKey "arc.staticip" "true" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.ip" "${IPADDR}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.netmask" "${NETMASK}" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "DHCP/Static IP" --colors --aspect 18 \
      --msgbox "Network set to STATIC!" 0 0
    else
      writeConfigKey "arc.staticip" "false" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.ip" "" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.netmask" "" "${USER_CONFIG_FILE}"
      dialog --backtitle "$(backtitle)" --title "DHCP/Static IP" --colors --aspect 18 \
      --msgbox "Network set to DHCP!" 0 0
    fi
}

###############################################################################
# allow downgrade dsm version
function downgradeMenu() {
  TEXT=""
  TEXT+="This feature will allow you to downgrade the installation by removing the VERSION file from the first partition of all disks.\n"
  TEXT+="Therefore, please insert all disks before continuing.\n"
  TEXT+="Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?"
  dialog --backtitle "$(backtitle)" --title "Allow downgrade installation" \
      --yesno "${TEXT}" 0 0
  [ $? -ne 0 ] && return 1
  (
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
      mount "${I}" "${TMP_PATH}/sdX1"
      [ -f "${TMP_PATH}/sdX1/etc/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc/VERSION"
      [ -f "${TMP_PATH}/sdX1/etc.defaults/VERSION" ] && rm -f "${TMP_PATH}/sdX1/etc.defaults/VERSION"
      sync
      umount "${I}"
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --title "Allow downgrade installation" \
      --progressbox "Removing ..." 20 70
  TEXT="Remove VERSION file for all disks completed."
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "${TEXT}" 0 0
}

###############################################################################
# Reset DSM password
function resetPassword() {
  rm -f "${TMP_PATH}/menu"
  mkdir -p "${TMP_PATH}/sdX1"
  for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
    mount ${I} "${TMP_PATH}/sdX1"
    if [ -f "${TMP_PATH}/sdX1/etc/shadow" ]; then
      for U in $(cat "${TMP_PATH}/sdX1/etc/shadow" | awk -F ':' '{if ($2 != "*" && $2 != "!!") {print $1;}}'); do
        grep -q "status=on" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/nulll
        [ $? -eq 0 ] && SS="SecureSignIn" || SS="            "
        printf "\"%-36s %-16s\"\n" "${U}" "${SS}" >>"${TMP_PATH}/menu"
      done
    fi
    umount "${I}"
    [ -f "${TMP_PATH}/menu" ] && break
  done
  rm -rf "${TMP_PATH}/sdX1"
  if [ ! -f "${TMP_PATH}/menu" ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
      --msgbox "The installed Syno system not found in the currently inserted disks!" 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
    --no-items --menu "Choose a User" 0 0 0  --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  USER="$(cat "${TMP_PATH}/resp" | awk '{print $1}')"
  [ -z "${USER}" ] && return
  while true; do
    dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
      --inputbox "Type a new Password for User ${USER}" 0 70 "${CMDLINE[${NAME}]}" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && break 2
    VALUE="$(<"${TMP_PATH}/resp")"
    [ -n "${VALUE}" ] && break
    dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
      --msgbox "Invalid Password" 0 0
  done
  NEWPASSWD="$(python -c "from passlib.hash import sha512_crypt;pw=\"${VALUE}\";print(sha512_crypt.using(rounds=5000).hash(pw))")"
  (
    mkdir -p "${TMP_PATH}/sdX1"
    for I in $(ls /dev/sd*1 2>/dev/null | grep -v "${LOADER_DISK_PART1}"); do
      mount "${I}" "${TMP_PATH}/sdX1"
      OLDPASSWD="$(cat "${TMP_PATH}/sdX1/etc/shadow" | grep "^${USER}:" | awk -F ':' '{print $2}')"
      [[ -n "${NEWPASSWD}" && -n "${OLDPASSWD}" ]] && sed -i "s|${OLDPASSWD}|${NEWPASSWD}|g" "${TMP_PATH}/sdX1/etc/shadow"
      sed -i "s|status=on|status=off|g" "${TMP_PATH}/sdX1/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
      sync
      umount "${I}"
    done
    rm -rf "${TMP_PATH}/sdX1"
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" \
    --progressbox "Resetting ..." 20 100
  dialog --backtitle "$(backtitle)" --colors --title "Reset DSM Password" --aspect 18 \
    --msgbox "Password reset completed." 0 0
}

###############################################################################
# modify bootipwaittime
function bootipwaittime() {
  ITEMS="$(echo -e "0 \n5 \n10 \n20 \n30 \n60 \n")"
  dialog --backtitle "$(backtitle)" --colors --title "Boot IP Waittime" \
    --default-item "${BOOTIPWAIT}" --no-items --menu "Choose Waittime(seconds)\nto get an IP" 0 0 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
  resp="$(cat ${TMP_PATH}/resp 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  BOOTIPWAIT=${resp}
  writeConfigKey "arc.bootipwait" "${BOOTIPWAIT}" "${USER_CONFIG_FILE}"
}

###############################################################################
# modify bootwaittime
function bootwaittime() {
  ITEMS="$(echo -e "0 \n5 \n10 \n20 \n30 \n60 \n")"
  dialog --backtitle "$(backtitle)" --title "Boot Waittime" \
    --default-item "${BOOTWAIT}" --no-items --menu "Choose Waittime(seconds)\nto init the Hardware" 0 0 0 ${ITEMS} \
    2>"${TMP_PATH}/resp"
  resp="$(cat ${TMP_PATH}/resp 2>/dev/null)"
  [ -z "${resp}" ] && return 1
  BOOTWAIT=${resp}
  writeConfigKey "arc.bootwait" "${BOOTWAIT}" "${USER_CONFIG_FILE}"
}

###############################################################################
# allow user to save modifications to disk
function saveMenu() {
  dialog --backtitle "$(backtitle)" --title "Save to Disk" \
      --yesno "Warning:\nDo not terminate midway, otherwise it may cause damage to the arc. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return 1
  dialog --backtitle "$(backtitle)" --title "Save to Disk" \
      --infobox "Saving ..." 0 0
  RDXZ_PATH="${TMP_PATH}/rdxz_tmp"
  mkdir -p "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; xz -dc <"${PART3_PATH}/initrd-arc" | cpio -idm) >/dev/null 2>&1 || true
  rm -rf "${RDXZ_PATH}/opt/arc"
  cp -Rf "/opt" "${RDXZ_PATH}"
  (cd "${RDXZ_PATH}"; find . 2>/dev/null | cpio -o -H newc -R root:root | xz --check=crc32 >"${PART3_PATH}/initrd-arc") || true
  rm -rf "${RDXZ_PATH}"
  dialog --backtitle "$(backtitle)" --colors --aspect 18 \
    --msgbox "Save to Disk is complete." 0 0
}

###############################################################################
# let user format disks from inside arc
function formatdisks() {
  rm -f "${TMP_PATH}/opts"
  while read -r POSITION NAME; do
    [[ -z "${POSITION}" || -z "${NAME}" ]] && continue
    echo "${POSITION}" | grep -q "${LOADER_DISK}" && continue
    echo "\"${POSITION}\" \"${NAME}\" \"off\"" >>"${TMP_PATH}/opts"
  done < <(ls -l /dev/disk/by-id/ | sed 's|../..|/dev|g' | grep -E "/dev/sd|/dev/nvme" | awk -F' ' '{print $NF" "$(NF-2)}' | sort -uk 1,1)
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --checklist "" 0 0 0 --file "${TMP_PATH}/opts" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return 1
  resp=$(<"${TMP_PATH}/resp")
  [ -z "${resp}" ] && return 1
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return 1
  if [ $(ls /dev/md* | wc -l) -gt 0 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
      --yesno "Warning:\nThe current hds is in raid, do you still want to format them?" 0 0
    [ $? -ne 0 ] && return 1
    for I in $(ls /dev/md*); do
      mdadm -S "${I}"
    done
  fi
  (
    for I in ${resp}; do
      echo y | mkfs.ext4 -T largefile4 "${I}" 2>&1
    done
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --progressbox "Formatting ..." 20 70
  dialog --backtitle "$(backtitle)" --colors --title "Format Disks" \
    --msgbox "Formatting is complete." 0 0
}

###############################################################################
# let user delete Loader Boot Files
function resetLoader() {
  if [[ -f "${ORI_ZIMAGE_FILE}" || -f "${ORI_RDGZ_FILE}" || -f "${MOD_ZIMAGE_FILE}" || -f "${MOD_RDGZ_FILE}" ]]; then
    # Clean old files
    rm -f "${ORI_ZIMAGE_FILE}" "${ORI_RDGZ_FILE}" "${MOD_ZIMAGE_FILE}" "${MOD_RDGZ_FILE}"
  fi
  if [ -f "${USER_CONFIG_FILE}" ]; then
    rm -f "${USER_CONFIG_FILE}"
  fi
  if [ -d "${UNTAR_PAT_PATH}" ]; then
    rm -rf "${UNTAR_PAT_PATH}"
  fi
  if [ ! -f "${USER_CONFIG_FILE}" ]; then
    touch "${USER_CONFIG_FILE}"
  fi
  initConfigKey "lkm" "prod" "${USER_CONFIG_FILE}"
  initConfigKey "model" "" "${USER_CONFIG_FILE}"
  initConfigKey "productver" "" "${USER_CONFIG_FILE}"
  initConfigKey "layout" "qwertz" "${USER_CONFIG_FILE}"
  initConfigKey "keymap" "de" "${USER_CONFIG_FILE}"
  initConfigKey "zimage-hash" "" "${USER_CONFIG_FILE}"
  initConfigKey "ramdisk-hash" "" "${USER_CONFIG_FILE}"
  initConfigKey "cmdline" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "synoinfo" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "addons" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "addons.acpid" "" "${USER_CONFIG_FILE}"
  initConfigKey "modules" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "arc" "{}" "${USER_CONFIG_FILE}"
  initConfigKey "arc.confdone" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.sn" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.mac1" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.staticip" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.directboot" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.remap" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.usbmount" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.patch" "random" "${USER_CONFIG_FILE}"
  initConfigKey "arc.pathash" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.paturl" "" "${USER_CONFIG_FILE}"
  initConfigKey "arc.bootipwait" "20" "${USER_CONFIG_FILE}"
  initConfigKey "arc.bootwait" "5" "${USER_CONFIG_FILE}"
  initConfigKey "arc.kernelload" "power" "${USER_CONFIG_FILE}"
  initConfigKey "arc.kernelpanic" "5" "${USER_CONFIG_FILE}"
  initConfigKey "arc.macsys" "hardware" "${USER_CONFIG_FILE}"
  initConfigKey "arc.bootcount" "0" "${USER_CONFIG_FILE}"
  initConfigKey "arc.odp" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.hddsort" "false" "${USER_CONFIG_FILE}"
  initConfigKey "arc.version" "${ARC_VERSION}" "${USER_CONFIG_FILE}"
  initConfigKey "device" "{}" "${USER_CONFIG_FILE}"
  MODEL="$(readConfigKey "model" "${USER_CONFIG_FILE}")"
  PRODUCTVER="$(readConfigKey "productver" "${USER_CONFIG_FILE}")"
  LKM="$(readConfigKey "lkm" "${USER_CONFIG_FILE}")"
  if [ -n "${MODEL}" ]; then
    PLATFORM="$(readModelKey "${MODEL}" "platform")"
    DT="$(readModelKey "${MODEL}" "dt")"
  fi
  CONFDONE="$(readConfigKey "arc.confdone" "${USER_CONFIG_FILE}")"
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  dialog --backtitle "$(backtitle)" --colors --title "Clean Old" \
    --msgbox "Clean is complete." 5 30
  clear
}

###############################################################################
# let user edit the grub.cfg
function editGrubCfg() {
  while true; do
    dialog --backtitle "$(backtitle)" --colors --title "Edit grub.cfg with caution" \
      --editbox "${GRUB_PATH}/grub.cfg" 0 0 2>"${TMP_PATH}/usergrub.cfg"
    [ $? -ne 0 ] && return
    mv -f "${TMP_PATH}/usergrub.cfg" "${GRUB_PATH}/grub.cfg"
    break
  done
}

###############################################################################
# Calls boot.sh to boot into DSM kernel/ramdisk
function boot() {
  BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
  [ "${BUILDDONE}" = "false" ] && dialog --backtitle "$(backtitle)" --title "Alert" \
    --yesno "Config changed, you need to rebuild the loader?" 0 0
  if [ $? -eq 0 ]; then
    make
  fi
  dialog --backtitle "$(backtitle)" --title "Arc Boot" \
    --infobox "Booting to DSM - Please stay patient!" 0 0
  sleep 2
  exec reboot
}

###############################################################################
###############################################################################

# Main loop
[ "${BUILDDONE}" = "true" ] && NEXT="3" || NEXT="1"
while true; do
  echo "= \"\Z4========== Main ==========\Zn \" "                                            >"${TMP_PATH}/menu"
  echo "1 \"Choose Model \" "                                                               >>"${TMP_PATH}/menu"
  if [ "${CONFDONE}" = "true" ]; then
    echo "2 \"Build Loader \" "                                                             >>"${TMP_PATH}/menu"
  fi
  if [ "${BUILDDONE}" = "true" ]; then
    echo "3 \"Boot Loader \" "                                                              >>"${TMP_PATH}/menu"
  fi
  echo "= \"\Z4========== Info ==========\Zn \" "                                           >>"${TMP_PATH}/menu"
  echo "a \"Sysinfo \" "                                                                    >>"${TMP_PATH}/menu"
  echo "= \"\Z4========= System =========\Zn \" "                                           >>"${TMP_PATH}/menu"
  if [ "${CONFDONE}" = "true" ]; then
    echo "b \"Addons \" "                                                                   >>"${TMP_PATH}/menu"
    echo "d \"Modules \" "                                                                  >>"${TMP_PATH}/menu"
    if [ "${ARCOPTS}" = "true" ]; then
      echo "4 \"\Z1Hide Arc Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    else
      echo "4 \"\Z1Show Arc Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    fi
    if [ "${ARCOPTS}" = "true" ]; then
      echo "= \"\Z4========== Arc ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "e \"DSM Version \" "                                                            >>"${TMP_PATH}/menu"
      echo "f \"Network Config \" "                                                         >>"${TMP_PATH}/menu"
      if [ "${DT}" = "false" ]; then
        echo "g \"Storage Map \" "                                                          >>"${TMP_PATH}/menu"
        echo "h \"USB Port Config \" "                                                      >>"${TMP_PATH}/menu"
      fi
      echo "p \"Arc Settings \" "                                                           >>"${TMP_PATH}/menu"
      echo ". \"DHCP/Static Loader IP \" "                                                  >>"${TMP_PATH}/menu"
    fi
    if [ "${ADVOPTS}" = "true" ]; then
      echo "5 \"\Z1Hide Advanced Options\Zn \" "                                            >>"${TMP_PATH}/menu"
    else
      echo "5 \"\Z1Show Advanced Options\Zn \" "                                            >>"${TMP_PATH}/menu"
    fi
    if [ "${ADVOPTS}" = "true" ]; then
      echo "= \"\Z4======== Advanced =======\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "j \"Cmdline \" "                                                                >>"${TMP_PATH}/menu"
      echo "k \"Synoinfo \" "                                                               >>"${TMP_PATH}/menu"
      echo "l \"Edit User Config \" "                                                       >>"${TMP_PATH}/menu"
    fi
    if [ "${BOOTOPTS}" = "true" ]; then
      echo "6 \"\Z1Hide Boot Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    else
      echo "6 \"\Z1Show Boot Options\Zn \" "                                                >>"${TMP_PATH}/menu"
    fi
    if [ "${BOOTOPTS}" = "true" ]; then
      echo "= \"\Z4========== Boot =========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "m \"DSM Kernelload: \Z4${KERNELLOAD}\Zn \" "                                    >>"${TMP_PATH}/menu"
      if [ "${DIRECTBOOT}" = "false" ]; then
        echo "i \"Boot IP Waittime: \Z4${BOOTIPWAIT}\Zn \" "                                >>"${TMP_PATH}/menu"
        echo "- \"Boot Waittime: \Z4${BOOTWAIT}\Zn \" "                                     >>"${TMP_PATH}/menu"
      fi
      echo "q \"Directboot: \Z4${DIRECTBOOT}\Zn \" "                                        >>"${TMP_PATH}/menu"
      if [ ${BOOTCOUNT} -gt 0 ]; then
        echo "r \"Reset Bootcount: \Z4${BOOTCOUNT}\Zn \" "                                  >>"${TMP_PATH}/menu"
      fi
    fi
    if [ "${DSMOPTS}" = "true" ]; then
      echo "7 \"\Z1Hide DSM Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    else
      echo "7 \"\Z1Show DSM Options\Zn \" "                                                 >>"${TMP_PATH}/menu"
    fi
    if [ "${DSMOPTS}" = "true" ]; then
      echo "= \"\Z4========== DSM ==========\Zn \" "                                        >>"${TMP_PATH}/menu"
      echo "s \"Allow DSM Downgrade \" "                                                    >>"${TMP_PATH}/menu"
      echo "t \"Change DSM Password \" "                                                    >>"${TMP_PATH}/menu"
      echo ", \"Official Driver Priority: \Z4${ODP}\Zn \" "                                 >>"${TMP_PATH}/menu"
      echo "/ \"Sort Drives: \Z4${HDDSORT}\Zn \" "                                          >>"${TMP_PATH}/menu"
      echo "o \"Switch MacSys: \Z4${MACSYS}\Zn \" "                                         >>"${TMP_PATH}/menu"
      echo "u \"Switch LKM version: \Z4${LKM}\Zn \" "                                       >>"${TMP_PATH}/menu"
    fi
  fi
  if [ "${DEVOPTS}" = "true" ]; then
    echo "8 \"\Z1Hide Dev Options\Zn \" "                                                   >>"${TMP_PATH}/menu"
  else
    echo "8 \"\Z1Show Dev Options\Zn \" "                                                   >>"${TMP_PATH}/menu"
  fi
  if [ "${DEVOPTS}" = "true" ]; then
    echo "= \"\Z4========== Dev ===========\Zn \" "                                         >>"${TMP_PATH}/menu"
    echo "v \"Save Modifications to Disk \" "                                               >>"${TMP_PATH}/menu"
    echo "n \"Edit Grub Config \" "                                                         >>"${TMP_PATH}/menu"
    echo "w \"Reset Loader \" "                                                             >>"${TMP_PATH}/menu"
    echo "+ \"\Z1Format Disk(s)\Zn \" "                                                     >>"${TMP_PATH}/menu"
  fi
  echo "= \"\Z4===== Loader Settings ====\Zn \" "                                           >>"${TMP_PATH}/menu"
  echo "x \"Backup/Restore/Recovery \" "                                                    >>"${TMP_PATH}/menu"
  echo "y \"Choose a keymap \" "                                                            >>"${TMP_PATH}/menu"
  echo "z \"Update \" "                                                                     >>"${TMP_PATH}/menu"
  echo "9 \"Credits \" "                                                                     >>"${TMP_PATH}/menu"
  echo "0 \"\Z1Exit\Zn \" "                                                                 >>"${TMP_PATH}/menu"

  dialog --clear --default-item ${NEXT} --backtitle "$(backtitle)" --colors \
    --title "Arc Menu" --menu "" 0 0 0 --file "${TMP_PATH}/menu" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && break
  case $(<"${TMP_PATH}/resp") in
    # Main Section
    1) arcMenu; NEXT="2" ;;
    2) make; NEXT="3" ;;
    3) boot && exit 0 || sleep 3 ;;
    # Info Section
    a) sysinfo; NEXT="a" ;;
    # System Section
    b) addonMenu; NEXT="b" ;;
    d) modulesMenu; NEXT="d" ;;
    !) fixSelection; NEXT="!" ;;
    # Arc Section
    4) [ "${ARCOPTS}" = "true" ] && ARCOPTS='false' || ARCOPTS='true'
       ARCOPTS="${ARCOPTS}"
       NEXT="4"
       ;;
    e) ONLYVERSION="true" && arcbuild; NEXT="e" ;;
    f) networkMenu; NEXT="f" ;;
    g) storageMenu; NEXT="g" ;;
    p) ONLYPATCH="true" && arcsettings; NEXT="p" ;;
    h) usbMenu; NEXT="h" ;;
    .) staticIPMenu; NEXT="." ;;
    # Advanced Section
    5) [ "${ADVOPTS}" = "true" ] && ADVOPTS='false' || ADVOPTS='true'
       ADVOPTS="${ADVOPTS}"
       NEXT="5"
       ;;
    j) cmdlineMenu; NEXT="j" ;;
    k) synoinfoMenu; NEXT="k" ;;
    l) editUserConfig; NEXT="l" ;;
    # Boot Section
    6) [ "${BOOTOPTS}" = "true" ] && BOOTOPTS='false' || BOOTOPTS='true'
       ARCOPTS="${BOOTOPTS}"
       NEXT="6"
       ;;
    m) [ "${KERNELLOAD}" = "kexec" ] && KERNELLOAD='power' || KERNELLOAD='kexec'
      writeConfigKey "arc.kernelload" "${KERNELLOAD}" "${USER_CONFIG_FILE}"
      NEXT="m"
      ;;
    i) bootipwaittime; NEXT="i" ;;
    -) bootwaittime; NEXT="-" ;;
    q) [ "${DIRECTBOOT}" = "false" ] && DIRECTBOOT='true' || DIRECTBOOT='false'
      grub-editenv "${GRUB_PATH}/grubenv" create
      writeConfigKey "arc.directboot" "${DIRECTBOOT}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.bootcount" "0" "${USER_CONFIG_FILE}"
      NEXT="q"
      ;;
    r)
      writeConfigKey "arc.bootcount" "0" "${USER_CONFIG_FILE}"
      BOOTCOUNT="$(readConfigKey "arc.bootcount" "${USER_CONFIG_FILE}")"
      NEXT="r"
      ;;
    # DSM Section
    7) [ "${DSMOPTS}" = "true" ] && DSMOPTS='false' || DSMOPTS='true'
      DSMOPTS="${DSMOPTS}"
      NEXT="7"
      ;;
    s) downgradeMenu; NEXT="s" ;;
    t) resetPassword; NEXT="t" ;;
    ,)
      [ "${ODP}" = "false" ] && ODP='true' || ODP='false'
      writeConfigKey "arc.odp" "${ODP}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      ;;
    /)
      [ "${HDDSORT}" = "true" ] && HDDSORT='false' || HDDSORT='true'
      writeConfigKey "arc.hddsort" "${HDDSORT}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="/"
      ;;
    o) [ "${MACSYS}" = "hardware" ] && MACSYS='custom' || MACSYS='hardware'
      writeConfigKey "arc.macsys" "${MACSYS}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="o"
      ;;
    u) [ "${LKM}" = "prod" ] && LKM='dev' || LKM='prod'
      writeConfigKey "lkm" "${LKM}" "${USER_CONFIG_FILE}"
      writeConfigKey "arc.builddone" "false" "${USER_CONFIG_FILE}"
      BUILDDONE="$(readConfigKey "arc.builddone" "${USER_CONFIG_FILE}")"
      NEXT="u"
      ;;
    # Dev Section
    8) [ "${DEVOPTS}" = "true" ] && DEVOPTS='false' || DEVOPTS='true'
      DEVOPTS="${DEVOPTS}"
      NEXT="8"
      ;;
    v) saveMenu; NEXT="v" ;;
    n) editGrubCfg; NEXT="n" ;;
    w) resetLoader; NEXT="w" ;;
    +) formatdisks; NEXT="+" ;;
    # Loader Settings
    x) backupMenu; NEXT="x" ;;
    y) keymapMenu; NEXT="y" ;;
    z) updateMenu; NEXT="z" ;;
    9) credits; NEXT="9" ;;
    0) break ;;
  esac
done
clear

# Inform user
echo -e "Call \033[1;34marc.sh\033[0m to configure loader"
echo
echo -e "Access:"
echo -e "IP: \033[1;34m${IP}\033[0m"
echo -e "User: \033[1;34mroot\033[0m"
echo -e "Password: \033[1;34marc\033[0m"
echo
echo -e "Web Terminal Access:"
echo -e "Address: \033[1;34mhttp://${IP}:7681\033[0m"