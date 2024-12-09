# ZMK Companion

A main menu macOS application communicate to ZMK powered HID device.

![screenshot](img/screenshot.png)

## Features:
- Synchronize master sound volume level to a [motorized fader](https://tech.alpsalpine.com/e/products/detail/RS60N11M9A0F/). Please checkout [this](https://github.com/badjeff/zmk-config/blob/0f1ed1f050bbced22127284eb78e1b7e48da5f47/config/boards/shields/zero36/zero36.keymap#L162) zmk-config repo for details if you are interested. 
🎬 WIP Video at [https://imgur.com/a/DuWsinB](https://imgur.com/a/DuWsinB)
*This function could be disable by commenting one line in source code*

- Highlight main menu icon as host-side layer indicator via hot keys [F17/F19/F20], which could be triggered by [zmk-output-behavior-listener](https://github.com/badjeff/zmk-output-behavior-listener) with ZMK config on below.

![menu icon colors](img/menu-icon-colors.png)

```dts
/*
  This example will be demo how to setup a 4 layers keymap. 
  Each layer will be assigned a Fn key to send a keypress to the host.
  And the NUM layer will be ignored due to no need of identicator for momentary layer.
*/
/* keymap layers */
#define DEF 0 // F17 - base layer
#define NUM 1 // N/A - number layer, which monentary layer, will be neglected
#define MSK 2 // F19 - mouse-key layer
#define MSC 3 // F20 - mouse-scroll layer, which tells `input-processor` transform trackball input to scroll wheel

/* setup zmk,output-behavior-listener to trigger function key F17 / F19 / F20 on layer state change */
#define OUTPUT_SOURCE_LAYER_STATE_CHANGE        1
/{
        /* enter and leave to MOUSE KEY layer */
        kp_f19_on_enter_mmv_layer {
                compatible = "zmk,output-behavior-listener";
                sources = < OUTPUT_SOURCE_LAYER_STATE_CHANGE >;
                layers = < MSK >; bindings = < &kp F19 >; tap-ms = <30>;
        };
        kp_f19_on_leave_to_mmv_layer {
                compatible = "zmk,output-behavior-listener";
                sources = < OUTPUT_SOURCE_LAYER_STATE_CHANGE >;
                invert-state; layers = < MSK >; bindings = < &kp F19 >; tap-ms = <30>;
        };

        /* enter and leave to MOUSE SCROLL layer */
        kp_f20_on_enter_msc_layer {
                compatible = "zmk,output-behavior-listener";
                sources = < OUTPUT_SOURCE_LAYER_STATE_CHANGE >;
                layers = < MSC >; bindings = < &kp F20 >; tap-ms = <30>;
        };
        kp_f20_on_leave_to_msc_layer {
                compatible = "zmk,output-behavior-listener";
                sources = < OUTPUT_SOURCE_LAYER_STATE_CHANGE >;
                invert-state; layers = < MSC >; bindings = < &kp F20 >; tap-ms = <30>;
        };

        /* back to base layers */
        kp_f17_on_leave_to_def_layer {
                compatible = "zmk,output-behavior-listener";
                sources = < OUTPUT_SOURCE_LAYER_STATE_CHANGE >;
                invert-state; layers = < DEF >; bindings = < &kp F17 >; tap-ms = <30>;
        };
        kp_f17_on_leave_to_num_layer {
                compatible = "zmk,output-behavior-listener";
                sources = < OUTPUT_SOURCE_LAYER_STATE_CHANGE >;
                invert-state; layers = < NUM >; bindings = < &kp F17 >; tap-ms = <30>;
        };
};
```
