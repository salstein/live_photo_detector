class M7AssetConstants {
  static const packageName = "live_photo_detector";
  static _M7LottieAssets lottie = _M7LottieAssets();
  static _M7ImageAssets images = _M7ImageAssets();
}

class _M7ImageAssets {
  String get _initPath {
    return "packages/live_photo_detector/src/assets";
  }

  String get mesh {
    return "$_initPath/final-mesh.png";
  }
}

class _M7LottieAssets {
  String get _initPath {
    return "src/assets/lottie";
  }

  String get livelynessStart {
    return "$_initPath/livelyness-start.json";
  }

  String get livelynessSuccess {
    return "$_initPath/livelyness-success.json";
  }

  String get stepCompleted {
    return "$_initPath/step_completed.json";
  }
}
