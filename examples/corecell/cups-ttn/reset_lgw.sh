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
detect_gpio_base() {
    GPIO_BASE=0

    # Method 1: Parse /sys/kernel/debug/gpio (requires root)
    if [ -r /sys/kernel/debug/gpio ]; then
        # Extract base from lines like "gpiochip0: GPIOs 512-569" or "GPIOs 571-624"
        GPIO_BASE=$(grep -m1 'gpiochip0:' /sys/kernel/debug/gpio 2>/dev/null | \
                    sed -n 's/.*GPIOs \([0-9]*\)-.*/\1/p')
    fi

    # Method 2: Check /sys/class/gpio/gpiochip*/base
    if [ -z "$GPIO_BASE" ] || [ "$GPIO_BASE" = "0" ]; then
        for chip in /sys/class/gpio/gpiochip*; do
            [ -f "$chip/base" ] || continue
            [ -f "$chip/label" ] || continue
            label=$(cat "$chip/label" 2>/dev/null)
            # Look for the main GPIO controller (pinctrl-bcm* or similar)
            case "$label" in
                *pinctrl*|*bcm*|*gpio*)
                    GPIO_BASE=$(cat "$chip/base" 2>/dev/null)
                    break
                    ;;
            esac
        done
    fi

    # Method 3: Fallback - detect by Raspberry Pi model
    if [ -z "$GPIO_BASE" ] || [ "$GPIO_BASE" = "0" ]; then
        if [ -f /proc/device-tree/model ]; then
            model=$(cat /proc/device-tree/model 2>/dev/null)
            case "$model" in
                *"Raspberry Pi 5"*)
                    GPIO_BASE=571
                    ;;
                *"Raspberry Pi 4"*|*"Raspberry Pi 3"*|*"Raspberry Pi Compute Module"*)
                    GPIO_BASE=512
                    ;;
                *"Raspberry Pi"*)
                    # Older models (Pi 1, Pi 2, Pi Zero)
                    GPIO_BASE=0
                    ;;
            esac
        fi
    fi

    # Final fallback
    [ -z "$GPIO_BASE" ] && GPIO_BASE=0

    echo "$GPIO_BASE"
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
  start) term; init; reset ;;
  stop)  reset; term ;;
  *) echo "Usage: $0 {start|stop}"; exit 1 ;;
esac

exit 0
