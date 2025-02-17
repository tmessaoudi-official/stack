https://gitlab.com/newbit/rootAVD

ANDROID_SERIAL="emulator-5554" adb root
ANDROID_SERIAL="emulator-5554" adb disable-verity
ANDROID_SERIAL="emulator-5554" adb reboot
ANDROID_SERIAL="emulator-5554" adb root
ANDROID_SERIAL="emulator-5554" adb remount

ANDROID_SERIAL="emulator-5554" adb pull /etc/hosts
ANDROID_SERIAL="emulator-5554" adb push hosts /etc/hosts

keep an empty blank line at the end of the file /etc/hosts