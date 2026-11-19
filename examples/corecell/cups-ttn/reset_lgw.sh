#!/bin/sh
# Reset script for SX1302 CoreCell concentrators on Raspberry Pi
# Supports multiple boards: WM1302 (Seeed), PG1302 (Dragino), and custom configs
# Auto-detects GPIO chip offset for different Raspberry Pi models

# =============================================================================
# Board Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_CONF="$SCRIPT_DIR/board.conf"

# Default values (WM1302 for backward compatibility)
SX1302_RESET_BCM=17
SX1302_POWER_EN_BCM=18
BOARD_TYPE="WM1302"

# Load board configuration if available
if [ -f "$BOARD_CONF" ]; then
    # Source the config file (reads BOARD_TYPE, SX1302_RESET_BCM, SX1302_POWER_EN_BCM)
    . "$BOARD_CONF"
    echo "Loaded board configuration: $BOARD_TYPE"
else
    echo "No board.conf found, using default WM1302 configuration"
fi

# Additional GPIO pins (board-specific, can be extended in board.conf)
# SX1261 reset pin - only used by some boards
SX1261_RESET_BCM=${SX1261_RESET_BCM:-5}

# AD5338R reset pin - leave empty to disable
AD5338R_RESET_BCM=${AD5338R_RESET_BCM:-}

# =============================================================================
# Auto-detect GPIO chip base offset for different Raspberry Pi models
# =============================================================================
# The 40-pin header is driven by one GPIO controller, identified by its label:
#   pinctrl-rp1      Raspberry Pi 5 / CM5 (RP1)
#   pinctrl-bcm2711  Raspberry Pi 4 / 400 / CM4
#   pinctrl-bcm2835  Raspberry Pi 1 / 2 / 3 / Zero / Zero 2
# Match the controller by this label, never by chip index or by a generic
# "gpio" substring: newer kernels renumber the chips (Pi 5 on 6.12.115: the
# RP1 header is gpiochip15, the first chips are gpio-brcmstb with base 512),
# and some kernels print debugfs lines without a "GPIOs <base>-<end>" range.
#
# Paths can be overridden (used by the tests).
GPIO_SYSFS_DIR="${GPIO_SYSFS_DIR:-/sys/class/gpio}"
GPIO_DEBUGFS="${GPIO_DEBUGFS:-/sys/kernel/debug/gpio}"
DT_MODEL_FILE="${DT_MODEL_FILE:-/proc/device-tree/model}"
HEADER_GPIO_LABELS="pinctrl-rp1 pinctrl-bcm2711 pinctrl-bcm2835"

detect_gpio_base() {
    # Method 0: explicit override from the environment or board.conf
    case "${GPIO_BASE:-}" in
        ''|*[!0-9]*) ;;
        *)
            echo "GPIO base $GPIO_BASE from GPIO_BASE override" >&2
            echo "$GPIO_BASE"
            return 0
            ;;
    esac

    # Method 1: sysfs chip labels (no root needed)
    for want in $HEADER_GPIO_LABELS; do
        for chip in "$GPIO_SYSFS_DIR"/gpiochip*; do
            [ -f "$chip/label" ] && [ -f "$chip/base" ] || continue
            if [ "$(cat "$chip/label" 2>/dev/null)" = "$want" ]; then
                base=$(cat "$chip/base" 2>/dev/null)
                echo "GPIO base $base from $chip ($want)" >&2
                echo "$base"
                return 0
            fi
        done
    done

    # Method 2: debugfs lines like
    #   "gpiochip15: GPIOs 571-624, parent: platform/1f000d0000.gpio, pinctrl-rp1:"
    # (requires root; lines without a range are skipped)
    if [ -r "$GPIO_DEBUGFS" ]; then
        for want in $HEADER_GPIO_LABELS; do
            base=$(sed -n "s/^gpiochip[0-9]*: GPIOs \([0-9]*\)-[0-9]*,.* $want:.*/\1/p" \
                   "$GPIO_DEBUGFS" 2>/dev/null | head -n 1)
            if [ -n "$base" ]; then
                echo "GPIO base $base from $GPIO_DEBUGFS ($want)" >&2
                echo "$base"
                return 0
            fi
        done
    fi

    # Method 3: Fallback - detect by Raspberry Pi model
    base=0
    if [ -f "$DT_MODEL_FILE" ]; then
        model=$(tr -d '\000' < "$DT_MODEL_FILE" 2>/dev/null)
        case "$model" in
            *"Raspberry Pi 5"*|*"Raspberry Pi Compute Module 5"*)
                base=571
                ;;
            *"Raspberry Pi 4"*|*"Raspberry Pi 3"*|*"Raspberry Pi Compute Module"*)
                base=512
                ;;
            *"Raspberry Pi"*)
                # Older models (Pi 1, Pi 2, Pi Zero)
                base=0
                ;;
        esac
    fi
    echo "GPIO base $base from model fallback" >&2
    echo "$base"
}

# =============================================================================
# Calculate actual sysfs GPIO numbers
# =============================================================================
GPIO_BASE=$(detect_gpio_base)

SX1302_RESET_PIN=$((GPIO_BASE + SX1302_RESET_BCM))
SX1302_POWER_EN_PIN=$((GPIO_BASE + SX1302_POWER_EN_BCM))
SX1261_RESET_PIN=$((GPIO_BASE + SX1261_RESET_BCM))

if [ -n "$AD5338R_RESET_BCM" ]; then
    AD5338R_RESET_PIN=$((GPIO_BASE + AD5338R_RESET_BCM))
else
    AD5338R_RESET_PIN=""
fi

echo "Board: $BOARD_TYPE"
echo "Detected GPIO base offset: $GPIO_BASE"
echo "  SX1302 Reset:    BCM $SX1302_RESET_BCM -> sysfs $SX1302_RESET_PIN"
echo "  SX1302 Power EN: BCM $SX1302_POWER_EN_BCM -> sysfs $SX1302_POWER_EN_PIN"
echo "  SX1261 Reset:    BCM $SX1261_RESET_BCM -> sysfs $SX1261_RESET_PIN"

WAIT_GPIO() { sleep 0.1; }

export_gpio() {
  pin="$1"
  [ -z "$pin" ] && return 0
  [ -d "/sys/class/gpio/gpio$pin" ] && return 0
  echo "$pin" > /sys/class/gpio/export 2>/dev/null || {
    echo "WARN: cannot export GPIO$pin (check numbering/offset)"
    return 0
  }
  WAIT_GPIO
}

set_dir() {
  pin="$1"; dir="$2"
  [ -z "$pin" ] && return 0
  echo "$dir" > "/sys/class/gpio/gpio$pin/direction" 2>/dev/null || true
  WAIT_GPIO
}

set_val() {
  pin="$1"; val="$2"
  [ -z "$pin" ] && return 0
  echo "$val" > "/sys/class/gpio/gpio$pin/value" 2>/dev/null || true
  WAIT_GPIO
}

unexport_gpio() {
  pin="$1"
  [ -z "$pin" ] && return 0
  [ -d "/sys/class/gpio/gpio$pin" ] || return 0
  echo "$pin" > /sys/class/gpio/unexport 2>/dev/null || true
  WAIT_GPIO
}

init() {
  export_gpio "$SX1302_RESET_PIN"
  export_gpio "$SX1261_RESET_PIN"
  export_gpio "$SX1302_POWER_EN_PIN"
  export_gpio "$AD5338R_RESET_PIN"

  set_dir "$SX1302_RESET_PIN" "out"
  set_dir "$SX1261_RESET_PIN" "out"
  set_dir "$SX1302_POWER_EN_PIN" "out"
  set_dir "$AD5338R_RESET_PIN" "out"
}

reset() {
  echo "CoreCell reset through GPIO$SX1302_RESET_PIN..."
  echo "SX1261 reset through GPIO$SX1261_RESET_PIN..."
  echo "CoreCell power enable through GPIO$SX1302_POWER_EN_PIN..."
  [ -n "$AD5338R_RESET_PIN" ] && echo "CoreCell ADC reset through GPIO$AD5338R_RESET_PIN..."

  set_val "$SX1302_POWER_EN_PIN" 1

  set_val "$SX1302_RESET_PIN" 1
  set_val "$SX1302_RESET_PIN" 0

  # optional SX1261
  set_val "$SX1261_RESET_PIN" 0
  set_val "$SX1261_RESET_PIN" 1

  # optional AD5338R
  if [ -n "$AD5338R_RESET_PIN" ]; then
    set_val "$AD5338R_RESET_PIN" 0
    set_val "$AD5338R_RESET_PIN" 1
  fi
}

term() {
  unexport_gpio "$SX1302_RESET_PIN"
  unexport_gpio "$SX1261_RESET_PIN"
  unexport_gpio "$SX1302_POWER_EN_PIN"
  unexport_gpio "$AD5338R_RESET_PIN"
}

case "$1" in
  start)  term; init; reset ;;
  stop)   reset; term ;;
  detect) ;;  # only print the detected pin mapping above, touch no GPIO
  *) echo "Usage: $0 {start|stop|detect}"; exit 1 ;;
esac

exit 0
