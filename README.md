# AntiDarkSword

Safe Theos UIKit mockup for a defensive AntiDarkSword-style application.

This project intentionally contains no sandbox escape, exploit, privilege
escalation, injection, kernel access, or bypass logic. The scan button only
animates local UI text.

## Build on Ubuntu

```bash
export THEOS="$HOME/theos"
cd AntiDarkSword
make package
```

If Theos cannot find an iPhoneOS SDK, copy your legitimate SDK into:

```bash
$THEOS/sdks/iPhoneOSXX.X.sdk
```

## Install on a jailbroken test device

Set the device IP and install:

```bash
export THEOS_DEVICE_IP=192.168.1.10
make package install
```

Or copy the `.deb` from `packages/` to the device and install it:

```bash
dpkg -i com.example.antidarksword_0.1.0_iphoneos-arm.deb
uicache -p /Applications/AntiDarkSword.app
```
