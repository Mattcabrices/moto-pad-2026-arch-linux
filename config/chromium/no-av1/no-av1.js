// Moto Pad (archpad): the MediaTek decoder plays H.264 and VP9 in hardware but not AV1, and Chromium decodes AV1 in
// software (dav1d), so YouTube's default AV1 costs about a core. Report AV1 as unsupported so YouTube picks VP9.
(() => {
  const isAv1 = (t) => /\bav01\b|\bav1\b/i.test(String(t || ''));
  for (const MS of [window.MediaSource, window.ManagedMediaSource]) {
    if (MS && MS.isTypeSupported) {
      const orig = MS.isTypeSupported.bind(MS);
      MS.isTypeSupported = (t) => (isAv1(t) ? false : orig(t));
    }
  }
  const canPlay = HTMLMediaElement.prototype.canPlayType;
  HTMLMediaElement.prototype.canPlayType = function (t) { return isAv1(t) ? '' : canPlay.call(this, t); };
  const mc = navigator.mediaCapabilities;
  if (mc && mc.decodingInfo) {
    const orig = mc.decodingInfo.bind(mc);
    mc.decodingInfo = (c) => (c && c.video && isAv1(c.video.contentType))
      ? Promise.resolve({ supported: false, smooth: false, powerEfficient: false })
      : orig(c);
  }
})();
