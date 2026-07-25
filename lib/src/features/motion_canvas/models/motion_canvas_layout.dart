enum MotionTemplate { travelDiary, sunsetStory, filmStrip, minimalMemory }

enum MotionTransition { softBlurBlend, softFade, lightLeak, blur, filmGrain }

enum MotionStyle { cinematic, film, clean, dusk }

enum MotionTool { layout, style, transition, music, export }

enum MotionExportFormat { motionPhoto, mp4 }

class MotionCanvasLayout {
  const MotionCanvasLayout({
    this.canvasWidth = 1080,
    this.maxClipHeight = 1120,
    this.cornerRadius = 24,
    this.overlap = 20,
  });

  final int canvasWidth;
  final int maxClipHeight;
  final double cornerRadius;
  final double overlap;

  double heightFor(double aspectRatio) {
    final natural = canvasWidth / aspectRatio.clamp(.45, 2.4);
    return natural.clamp(360, maxClipHeight).toDouble();
  }
}

extension MotionTemplateCopy on MotionTemplate {
  String title(bool zh) => switch (this) {
    MotionTemplate.travelDiary => zh ? '旅行日记' : 'Travel Diary',
    MotionTemplate.sunsetStory => zh ? '落日故事' : 'Sunset Story',
    MotionTemplate.filmStrip => zh ? '胶片叙事' : 'Film Strip',
    MotionTemplate.minimalMemory => zh ? '极简记忆' : 'Minimal Memory',
  };

  String subtitle(bool zh) => switch (this) {
    MotionTemplate.travelDiary =>
      zh ? '景色 · 人物 · 细节' : 'Place · People · Detail',
    MotionTemplate.sunsetStory =>
      zh ? '光线 · 环境 · 剪影' : 'Light · Place · Silhouette',
    MotionTemplate.filmStrip => zh ? '颗粒 · 暖调 · 连续' : 'Grain · Warmth · Rhythm',
    MotionTemplate.minimalMemory =>
      zh ? '留白 · 呼吸 · 克制' : 'Space · Breath · Restraint',
  };
}
