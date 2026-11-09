# Runs on the tablet: the Renderer thread (and any thread inside hybris/Android code) from /tmp/ff-bt.txt.
awk '/^Thread /{show = ($0 ~ /Renderer|Compositor|WRRenderBackend|SceneBuilder/)} show' /tmp/ff-bt.txt | cut -c1-170 | head -60
echo "--- threads inside hybris/android/mali:"
grep -E '^Thread |hybris|libEGL|libGLES|mali|android' /tmp/ff-bt.txt | grep -B1 -E 'hybris|libEGL|libGLES|mali|android' | grep '^Thread' | cut -c1-120 | head
