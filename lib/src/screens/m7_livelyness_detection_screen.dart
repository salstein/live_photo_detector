import 'dart:async';
import 'dart:ui' as ui;
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:collection/collection.dart';
import 'package:live_photo_detector/index.dart';
import 'package:live_photo_detector/src/core/helpers/analysistoinputimage.dart';

List<CameraDescription> availableCams = [];

class M7LivelynessDetectionScreen extends StatefulWidget {
  final M7DetectionConfig config;
  const M7LivelynessDetectionScreen({
    required this.config,
    super.key,
  });

  @override
  State<M7LivelynessDetectionScreen> createState() =>
      _MLivelyness7DetectionScreenState();
}

class _MLivelyness7DetectionScreenState
    extends State<M7LivelynessDetectionScreen> {
  //* MARK: - Private Variables
  //? =========================================================
  late bool _isInfoStepCompleted;
  late final List<M7LivelynessStepItem> steps;
  CameraController? _cameraController;
  CameraState? _cameraState;
  CustomPaint? _customPaint;
  int _cameraIndex = 0;
  bool _isBusy = false;
  final GlobalKey<M7LivelynessDetectionStepOverlayState> _stepsKey =
      GlobalKey<M7LivelynessDetectionStepOverlayState>();
  bool _isProcessingStep = false;
  bool _didCloseEyes = false;
  bool _isTakingPicture = false;
  Timer? _timerToDetectFace;
  bool _isCaptureButtonVisible = false;
  late final List<M7LivelynessStepItem> _steps;
  List<Face> _previousFaces = [];
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 10;

  //* MARK: - Life Cycle Methods
  //? =========================================================
  @override
  void initState() {
    _preInitCallBack();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _postFrameCallBack(),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _timerToDetectFace?.cancel();
    _timerToDetectFace = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  //* MARK: - Private Methods for Business Logic
  //? =========================================================
  void _preInitCallBack() {
    _steps = widget.config.steps;
    _isInfoStepCompleted = !widget.config.startWithInfoScreen;
  }

  void _postFrameCallBack() async {
    if (Platform.isAndroid) {
      _startLiveFeed();
    } else {
      availableCams = await availableCameras();
      if (availableCams.any(
        (element) =>
            element.lensDirection == CameraLensDirection.front &&
            element.sensorOrientation == 90,
      )) {
        _cameraIndex = availableCams.indexOf(
          availableCams.firstWhere((element) =>
              element.lensDirection == CameraLensDirection.front &&
              element.sensorOrientation == 90),
        );
      } else {
        _cameraIndex = availableCams.indexOf(
          availableCams.firstWhere(
            (element) => element.lensDirection == CameraLensDirection.front,
          ),
        );
      }
      if (!widget.config.startWithInfoScreen) {
        _startLiveFeed();
      }
    }
  }

  void _startTimer() {
    _timerToDetectFace = Timer(
      Duration(seconds: widget.config.maxSecToDetect),
      () {
        _timerToDetectFace?.cancel();
        _timerToDetectFace = null;
        if (widget.config.allowAfterMaxSec) {
          _isCaptureButtonVisible = true;
          setState(() {});
          return;
        }
        _onDetectionCompleted(
          imgToReturn: null,
        );
      },
    );
  }

  void _startLiveFeed() async {
    if (Platform.isAndroid) {
      CameraAwesomeBuilder.previewOnly(
        previewFit: CameraPreviewFit.contain,
        sensorConfig: SensorConfig.single(
          sensor: Sensor.position(SensorPosition.front),
          aspectRatio: CameraAspectRatios.ratio_1_1,
        ),
        onImageForAnalysis: (img) => _analyzeImage(img),
        imageAnalysisConfig: AnalysisConfig(
          androidOptions: const AndroidAnalysisOptions.nv21(
            width: 250,
          ),
          maxFramesPerSecond: 5,
        ),
        builder: (state, preview) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // _MyPreviewDecoratorWidget(
              //   cameraState: state,
              //   faceDetectionStream: _faceDetectionController,
              //   previewSize: preview.previewSize,
              //   previewRect: preview.previewRect,
              // ),
              if (_customPaint != null) _customPaint!,
              M7LivelynessDetectionStepOverlay(
                key: _stepsKey,
                steps: _steps,
                onCompleted: () => Future.delayed(
                  const Duration(milliseconds: 500),
                  () => _takePicture(),
                ),
              ),
              Visibility(
                visible: _isCaptureButtonVisible,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Spacer(flex: 20),
                    MaterialButton(
                      onPressed: () => _takePicture(),
                      color: widget.config.captureButtonColor ??
                          Theme.of(context).primaryColor,
                      textColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                      shape: const CircleBorder(),
                      child: const Icon(Icons.camera_alt, size: 24),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 10),
                  child: GestureDetector(
                    onTap: _switchCamera,
                    child: const CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black,
                      child: Icon(
                        Icons.switch_camera,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      final camera = availableCams[_cameraIndex];
      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        _cameraController?.initialize().then((_) {
          if (!mounted) {
            return;
          }
          _startTimer();
          _cameraController?.startImageStream(_processCameraImage);
          setState(() {});
        });
        // await _cameraController!.initialize();
        // if (!mounted) return;
        // _startTimer();
        // await _cameraController!.startImageStream(_processCameraImage);
        // setState(() {});
      } catch (e) {
        print("Error starting camera feed: $e");
      }
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    final camera = availableCams[_cameraIndex];
    final imageRotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (imageRotation == null) return;

    final inputImageFormat = InputImageFormatValue.fromRawValue(
      cameraImage.format.raw,
    );
    if (inputImageFormat == null) return;
    final planeData = cameraImage.planes.first.bytesPerRow;

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: planeData,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );

    _processImage(inputImage);
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (_isBusy) {
      return;
    }
    _isBusy = true;
    final faces = await M7MLHelper.instance.processInputImage(inputImage);

    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      if (faces.isNotEmpty) {
        if (_detectMotion(faces.first)) {
          _stableFrameCount = 0;
        } else {
          _stableFrameCount++;
        }
        if (_stableFrameCount >= _requiredStableFrames) {
          // If the face is too stable for too long, it might be a static image
          _resetSteps();
          // Optionally, notify the user that a live face is required
        } else {
          // Continue with existing detection logic
          _detect(
              face: faces.first,
              step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step);
        }

        _previousFaces = faces;
        final firstFace = faces.first;
        final painter = M7FaceDetectorPainter(
          firstFace,
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
        );
        _customPaint = CustomPaint(
          painter: painter,
          child: Container(
            color: Colors.transparent,
            height: double.infinity,
            width: double.infinity,
            margin: EdgeInsets.only(
                // top: MediaQuery.of(context).padding.top,
                // bottom: MediaQuery.of(context).padding.bottom,
                ),
          ),
        );
        if (_isProcessingStep &&
            _steps[_stepsKey.currentState?.currentIndex ?? 0].step ==
                M7LivelynessStep.blink) {
          if (_didCloseEyes) {
            if ((faces.first.leftEyeOpenProbability ?? 1.0) < 0.75 &&
                (faces.first.rightEyeOpenProbability ?? 1.0) < 0.75) {
              await _completeStep(
                step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step,
              );
            }
          }
        }
        _detect(
          face: faces.first,
          step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step,
        );
      } else {
        _resetSteps();
      }
    } else {
      _resetSteps();
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _completeStep({
    required M7LivelynessStep step,
  }) async {
    final int indexToUpdate = _steps.indexWhere(
      (p0) => p0.step == step,
    );

    _steps[indexToUpdate] = _steps[indexToUpdate].copyWith(
      isCompleted: true,
    );
    if (mounted) {
      setState(() {});
    }
    await _stepsKey.currentState?.nextPage();
    _stopProcessing();
  }

  void _takePicture() async {
    if (Platform.isAndroid) {
      try {
        if (_cameraState == null) {
          if (mounted) _onDetectionCompleted(); // Add this check
          return;
        }
        if (_isTakingPicture) {
          return;
        }
        setState(
          () => _isTakingPicture = true,
        );
        _cameraState?.when(
          onPhotoMode: (p0) => Future.delayed(
            const Duration(milliseconds: 500),
            () => p0.takePhoto().then(
              (value) {
                // if (detectedFace != null) {
                //   cropImage(File(value), detectedFace!.boundingBox);
                // }
                final filePath = value.path;
                print('$filePath kya aaya isme');
                final xFile = XFile(filePath!);

                _onDetectionCompleted(
                  imgToReturn: xFile,
                );
              },
            ),
          ),
        );
      } catch (e) {
        print("$e yai error aaya");
        _startLiveFeed();
      }
    } else {
      try {
        if (_cameraController == null) return;
        // if (face == null) return;
        if (_isTakingPicture) {
          return;
        }
        setState(
          () => _isTakingPicture = true,
        );
        await _cameraController?.stopImageStream();
        final XFile? clickedImage = await _cameraController?.takePicture();
        if (clickedImage == null) {
          _startLiveFeed();
          return;
        }
        _onDetectionCompleted(imgToReturn: clickedImage);
      } catch (e) {
        _startLiveFeed();
      }
    }
  }

  void _onDetectionCompleted({
    XFile? imgToReturn,
  }) {
    if (!mounted) return; // Add this line

    final String? imgPath = imgToReturn?.path;
    print('$imgPath image ki value');
    Navigator.of(context).pop(imgPath);
  }

  void _resetSteps() async {
    for (var p0 in _steps) {
      final int index = _steps.indexWhere(
        (p1) => p1.step == p0.step,
      );
      _steps[index] = _steps[index].copyWith(
        isCompleted: false,
      );
    }
    _customPaint = null;
    _didCloseEyes = false;
    if (_stepsKey.currentState?.currentIndex != 0) {
      _stepsKey.currentState?.reset();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _startProcessing() {
    if (!mounted) {
      return;
    }
    setState(
      () => _isProcessingStep = true,
    );
  }

  void _stopProcessing() {
    if (!mounted) {
      return;
    }
    setState(
      () => _isProcessingStep = false,
    );
  }

  void _detect({
    required Face face,
    required M7LivelynessStep step,
  }) async {
    if (_isProcessingStep) {
      return;
    }
    switch (step) {
      case M7LivelynessStep.motion:
        if (_detectMotion(face)) {
          _stableFrameCount = 0;
          _startProcessing();
          await _completeStep(step: step);
        } else {
          _stableFrameCount++;
          if (_stableFrameCount >= _requiredStableFrames) {
            // If the face is too stable for too long, it might be a static image
            _resetSteps();
            // Optionally, notify the user that motion is required
          }
        }
        break;
      case M7LivelynessStep.blink:
        final M7BlinkDetectionThreshold? blinkThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7BlinkDetectionThreshold,
        ) as M7BlinkDetectionThreshold?;
        if ((face.leftEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.leftEyeProbability ?? 0.25) &&
            (face.rightEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.rightEyeProbability ?? 0.25)) {
          _startProcessing();
          if (mounted) {
            setState(
              () => _didCloseEyes = true,
            );
          }
        }
        break;
      case M7LivelynessStep.turnLeft:
        final M7HeadTurnDetectionThreshold? headTurnThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7HeadTurnDetectionThreshold,
        ) as M7HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) >
            (headTurnThreshold?.rotationAngle ?? 45)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case M7LivelynessStep.turnRight:
        final M7HeadTurnDetectionThreshold? headTurnThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7HeadTurnDetectionThreshold,
        ) as M7HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) >
            (headTurnThreshold?.rotationAngle ?? -50)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case M7LivelynessStep.smile:
        final M7SmileDetectionThreshold? smileThreshold =
            M7LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is M7SmileDetectionThreshold,
        ) as M7SmileDetectionThreshold?;
        if ((face.smilingProbability ?? 0) >
            (smileThreshold?.probability ?? 0.75)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
    }
  }

  //* MARK: - Private Methods for UI Components
  //? =========================================================
  Widget _buildBody() {
    return Stack(
      children: [
        _isInfoStepCompleted
            ? _buildDetectionBody()
            : M7LivelynessInfoWidget(
                onStartTap: () {
                  if (mounted) {
                    setState(
                      () => _isInfoStepCompleted = true,
                    );
                  }
                  _startLiveFeed();
                },
              ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(
              right: 10,
              top: 10,
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black,
              child: IconButton(
                onPressed: () => _onDetectionCompleted(
                  imgToReturn: null,
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _detectMotion(Face currentFace) {
    if (_previousFaces.isEmpty) return true;

    final previousFace = _previousFaces.first;
    const double threshold = 2.0; // Adjust this value based on your needs

    // Check for changes in face position or expression
    return (currentFace.boundingBox.left - previousFace.boundingBox.left)
                .abs() >
            threshold ||
        (currentFace.boundingBox.top - previousFace.boundingBox.top).abs() >
            threshold ||
        (currentFace.headEulerAngleY! - previousFace.headEulerAngleY!).abs() >
            threshold ||
        (currentFace.headEulerAngleZ! - previousFace.headEulerAngleZ!).abs() >
            threshold;
  }

  void _switchCamera() async {
    if (availableCams.length < 2) {
      return;
    }
    _cameraIndex = (_cameraIndex + 1) % 2;
    await _cameraController?.dispose();
    _cameraController = null;
    _startLiveFeed();
  }

  bool _isAnyStepCompleted() {
    return _steps.any((step) => step.isCompleted);
  }

  Future _analyzeImage(AnalysisImage img) async {
    final inputImage = img.toInputImage();
    try {
      _processImage(inputImage);
    } catch (error) {
      debugPrint("...sending image resulted error $error");
    }
  }

  Widget _buildDetectionBody() {
    if (Platform.isAndroid) {
      return Stack(
        children: [
          _isInfoStepCompleted
              ? CameraAwesomeBuilder.custom(
                  saveConfig: SaveConfig.photo(),
                  previewFit: CameraPreviewFit.contain,
                  sensorConfig: SensorConfig.single(
                    sensor: Sensor.position(SensorPosition.front),
                    aspectRatio: CameraAspectRatios.ratio_1_1,
                  ),
                  onImageForAnalysis: (img) => _analyzeImage(img),
                  imageAnalysisConfig: AnalysisConfig(
                    androidOptions: const AndroidAnalysisOptions.nv21(
                      width: 250,
                    ),
                    maxFramesPerSecond: 5,
                  ),
                  builder: (state, preview) {
                    _cameraState = state;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // if (_customPaint != null) _customPaint!,
                      ],
                    );
                  },
                )
              : M7LivelynessInfoWidget(
                  onStartTap: () {
                    if (!mounted) {
                      return;
                    }
                    _startTimer();
                    setState(
                      () => _isInfoStepCompleted = true,
                    );
                  },
                ),
          if (_isInfoStepCompleted)
            M7LivelynessDetectionStepOverlay(
              key: _stepsKey,
              steps: _steps,
              onCompleted: () => _takePicture(),
            ),
          Visibility(
            visible: _isCaptureButtonVisible,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(
                  flex: 20,
                ),
                MaterialButton(
                  onPressed: () => _takePicture(),
                  color: widget.config.captureButtonColor ??
                      Theme.of(context).primaryColor,
                  textColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  shape: const CircleBorder(),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 24,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(
                right: 10,
                top: 10,
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.black,
                child: IconButton(
                  onPressed: () {
                    _onDetectionCompleted(
                      imgToReturn: null,
                    );
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      if (_cameraController == null ||
          _cameraController?.value.isInitialized == false) {
        return const Center(
          child: CircularProgressIndicator.adaptive(),
        );
      }
      final size = MediaQuery.of(context).size;
      var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
      if (scale < 1) scale = 1 / scale;
      final Widget cameraView = CameraPreview(_cameraController!);
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: cameraView,
          ),
          IgnorePointer(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 5.0,
                sigmaY: 5.0,
              ),
              child: Container(
                color: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          Center(
            child: cameraView,
          ),
          if (_customPaint != null) _customPaint!,
          M7LivelynessDetectionStepOverlay(
            key: _stepsKey,
            steps: _steps,
            onCompleted: () => Future.delayed(
              const Duration(milliseconds: 500),
              () => _takePicture(),
            ),
          ),
          Visibility(
            visible: _isCaptureButtonVisible,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(
                  flex: 20,
                ),
                MaterialButton(
                  onPressed: () => _takePicture(),
                  color: widget.config.captureButtonColor ??
                      Theme.of(context).primaryColor,
                  textColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  shape: const CircleBorder(),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 24,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      _switchCamera();
                    },
                    child: const CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.black,
                      child: Icon(
                        Icons.switch_camera,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
  }
}
