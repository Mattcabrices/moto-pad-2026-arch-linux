# Runs as root on the tablet: why is the runtime APEX (linker64) missing?
R=/opt/android-full; I=/opt/android-img
ls $R/system/apex | grep -iE "runtime|art|i18n|vndk"
ls -la $R/apex | grep -iE "runtime" | cut -c1-120
for f in $I/apex/*runtime*.img; do echo "$f: $(file -b "$f" | cut -c1-60)"; done
mount | grep -c "$R/apex"
