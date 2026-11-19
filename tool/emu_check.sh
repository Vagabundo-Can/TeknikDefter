#!/bin/bash
# Emülatörde APK'yı kur, aç, çökme kaydı + ekran görüntüsü al
set -x
mkdir -p diag
adb install -r "$1" > diag/install.txt 2>&1
adb logcat -c
adb shell am start -W -n com.vagabundo.teknik_defter/.MainActivity > diag/start.txt 2>&1
sleep 25
adb exec-out screencap -p > diag/ekran_1.png
adb shell pidof com.vagabundo.teknik_defter > diag/pid.txt 2>&1
adb logcat -d -v time > diag/logcat_full.txt
grep -E "AndroidRuntime|FATAL|flutter|teknik_defter" diag/logcat_full.txt | head -400 > diag/logcat_errors.txt
true
