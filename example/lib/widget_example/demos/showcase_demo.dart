enum ShowcaseDemo { explodingButton, waterList, crtTerminal, widgetTransition }

extension ShowcaseDemoInfo on ShowcaseDemo {
  String get title {
    switch (this) {
      case ShowcaseDemo.explodingButton:
        return '💥 Exploding Button';
      case ShowcaseDemo.waterList:
        return '🌊 Liquid ListView';
      case ShowcaseDemo.crtTerminal:
        return '📺 CRT Terminal';
      case ShowcaseDemo.widgetTransition:
        return '🔀 Digital Transition';
    }
  }

  String get subtitle {
    switch (this) {
      case ShowcaseDemo.explodingButton:
        return 'Percentiles [0.3, 0.7] x [0.45, 0.55]';
      case ShowcaseDemo.waterList:
        return 'Scrollable list & switches with water caustics';
      case ShowcaseDemo.crtTerminal:
        return 'Real-time keyboard input with scanlines & bloom';
      case ShowcaseDemo.widgetTransition:
        return 'Two interactive widget channels transitioning';
    }
  }

  String get description {
    switch (this) {
      case ShowcaseDemo.explodingButton:
        return 'The Exploding Button demonstrates WidgetChannel with autoRender = true at percentiles [0.3, 0.7] x [0.45, 0.55]. Click the button to trigger a shatter explosion with shockwave and particle sparks!';
      case ShowcaseDemo.waterList:
        return 'The Liquid ListView showcases live interactive scrolling, counters, and switches with refractive liquid water caustics and mouse-following ripple waves.';
      case ShowcaseDemo.crtTerminal:
        return 'The Retro CRT Terminal accepts live keyboard input into Flutter TextFields through barrel curvature, RGB phosphor shadow-masks, and scanlines.';
      case ShowcaseDemo.widgetTransition:
        return 'The Digital Transition demonstrates user-controlled page transitions! Click the right arrow button (→) on Page A or in the banner to wipe to Page B, and the back arrow (←) to transition back.';
    }
  }
}
