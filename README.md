# SqueezeDSP Native DSD

An LMS plugin based on [SqueezeDSP 0.1.72](https://github.com/Foxenfurter/SqueezeDSP)
by Jonathan Fox. It retains SqueezeDSP processing for PCM and preserves LMS's
native DSF/DFF passthrough profiles. The upstream project is MIT licensed; its
license and attribution are included in this repository and plugin package.

This is a separate LMS plugin named **SqueezeDSP Native DSD** with module ID
`Plugins::SqueezeDSPNativeDSD::Plugin`. It has a separate settings directory.
Keep the original SqueezeDSP plugin **disabled**. Running both on the same LMS
server would cause their conversion rules to compete.

## Install through LMS

1. In **Settings → Manage Plugins**, disable the original SqueezeDSP plugin
   and restart LMS.
2. In **Additional Repositories**, add:

   `https://raw.githubusercontent.com/moonknight82/squeezedsp-native-dsd/main/extensions.xml`

3. Save settings. Select **SqueezeDSP Native DSD** from the third-party plugin
   list and apply. Let LMS download and restart.
4. Under **Settings → Advanced → File Types**, leave **Prefer native format
   whenever possible** enabled. Keep native DSF and DFF playback enabled.
   Leave DSDPlayer disabled for the initial test.

The new plugin stores its DSP settings separately from upstream SqueezeDSP.
If you have presets or impulse files in the original plugin, back up LMS's
`/config` volume before migrating them.

## Verify playback

Play a DSF on a Squeezelite player configured for native DSD. On a Raspberry
Pi with the Fosi ZD3, `cat /proc/asound/ZD3/pcm0p/sub0/hw_params` should show
`format: DSD_U32_BE`. Then play a PCM track and confirm that DSP is applied.

The package passed a local conversion-table test and ZIP integrity check.
Playback on a live LMS system has not yet been verified.

## Source and license

The [plugin ZIP](https://github.com/moonknight82/squeezedsp-native-dsd/releases)
contains the full plugin source and binaries. The native passthrough change is
in `SqueezeDSPNativeDSD/Configuration.pm`. See [LICENSE](LICENSE) for the MIT
terms from the upstream project.
