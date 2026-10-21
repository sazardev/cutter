import 'package:cutter/features/editor/data/sample_models.dart';

// Sample data that stands in for the missing domain until the engine exists.




/// Identifier of the sample project.
const String _sampleProjectId = 'project-sample';

/// Returns the starting project: one video, one image and one audio layer.
SampleProject sampleProject() {
  return const SampleProject(
    id: _sampleProjectId,
    name: 'Sample',
    layers: <SampleLayer>[
      SampleLayer(
        id: 'layer-video',
        kind: LayerKind.video,
        name: 'Video',
        clips: <SampleClip>[
          SampleClip(
            id: 'clip-beach',
            name: 'Beach.mp4',
            kind: LayerKind.video,
            startMs: 0,
            durationMs: 8000,
            inMs: 0,
            outMs: 8000,
          ),
        ],
      ),
      SampleLayer(
        id: 'layer-image',
        kind: LayerKind.image,
        name: 'Image',
        clips: <SampleClip>[
          SampleClip(
            id: 'clip-logo',
            name: 'Logo.png',
            kind: LayerKind.image,
            startMs: 1000,
            durationMs: 4000,
            inMs: 0,
            outMs: 4000,
          ),
        ],
      ),
      SampleLayer(
        id: 'layer-audio',
        kind: LayerKind.audio,
        name: 'Audio',
        clips: <SampleClip>[
          SampleClip(
            id: 'clip-song',
            name: 'Song.mp3',
            kind: LayerKind.audio,
            startMs: 0,
            durationMs: 10000,
            inMs: 0,
            outMs: 10000,
          ),
        ],
      ),
    ],
  );
}

/// Media offered by the picker; `broken.mov` is unsupported on purpose.
const List<SampleAsset> sampleMediaAssets = <SampleAsset>[
  SampleAsset(
    id: 'asset-city',
    name: 'City.mp4',
    kind: LayerKind.video,
    durationMs: 6000,
    supported: true,
  ),
  SampleAsset(
    id: 'asset-sunset',
    name: 'Sunset.jpg',
    kind: LayerKind.image,
    durationMs: 3000,
    supported: true,
  ),
  SampleAsset(
    id: 'asset-beat',
    name: 'Beat.mp3',
    kind: LayerKind.audio,
    durationMs: 8000,
    supported: true,
  ),
  SampleAsset(
    id: 'asset-broken',
    name: 'broken.mov',
    kind: LayerKind.video,
    durationMs: 5000,
    supported: false,
  ),
];

/// Filters the user can apply to a clip.
const List<SampleFilter> sampleFilters = <SampleFilter>[
  SampleFilter(id: 'filter-noir', name: 'Noir'),
  SampleFilter(id: 'filter-warm', name: 'Warm'),
  SampleFilter(id: 'filter-cool', name: 'Cool'),
  SampleFilter(id: 'filter-fade', name: 'Fade'),
];

/// Presets start empty; the user saves their own.
const List<SamplePreset> samplePresets = <SamplePreset>[];

/// Templates that create a project once their slots are filled.
const List<SampleTemplate> sampleTemplates = <SampleTemplate>[
  SampleTemplate(
    id: 'template-vlog-intro',
    name: 'Vlog intro',
    slots: <SampleSlot>[
      SampleSlot(id: 'slot-video', kind: LayerKind.video),
      SampleSlot(id: 'slot-audio', kind: LayerKind.audio),
    ],
  ),
];

/// Device permissions in the sample: microphone granted, camera denied.
const ({bool microphone, bool camera}) samplePermissions = (
  microphone: true,
  camera: false,
);
