for m in wmt_drv connfem wmt_chrdev_wifi connadp conninfra mtk_ccci cfg80211 mac80211 wlan_drv_gen4m_6835; do grep -q "^$m " /proc/modules && echo "$m loaded" || echo "$m NOT loaded"; done
