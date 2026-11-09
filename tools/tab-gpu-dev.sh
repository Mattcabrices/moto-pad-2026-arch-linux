ls -la /dev/mali* /dev/dma_heap/ 2>&1 | head -8
grep -E "^(mali_kbase|mali_mgm|ged|mtk_gpu)" /proc/modules | cut -d" " -f1 | tr "
" " "; echo
