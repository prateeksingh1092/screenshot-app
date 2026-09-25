import { Audio, Video } from "@remotion/media";
import {
  AbsoluteFill,
  Composition,
  Easing,
  Freeze,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const FPS = 30;
const WIDTH = 1920;
const HEIGHT = 1080;

const sec = (time: number) => Math.round(time * FPS);

type Line = { file: string; text: string; at: number; dur: number };

type Beat = {
  start: number;
  end: number;
  hold: number;
  lines: Line[];
};

const beats: Beat[] = [
  {
    start: 0.6,
    end: 4.2,
    hold: 1.6,
    lines: [{ file: "v1.m4a", text: "You need the lamp. Not the whole desktop.", at: 0.5, dur: 2.45 }],
  },
  {
    start: 3.7,
    end: 15.3,
    hold: 4.2,
    lines: [
      {
        file: "v2.m4a",
        text: "Command shift 4. That grid is the pixels under the pointer, frozen before the dimmer, so the border stays out of the sample.",
        at: 2.2,
        dur: 7.1,
      },
    ],
  },
  {
    start: 16.5,
    end: 22.6,
    hold: 2.2,
    lines: [{ file: "v3.m4a", text: "A black bar. An arrow on the price. Cropped to the point.", at: 0.4, dur: 3.43 }],
  },
  {
    start: 22.6,
    end: 28.0,
    hold: 2.2,
    lines: [{ file: "v4.m4a", text: "The whole window, when you want it. Command shift 5.", at: 0.4, dur: 3.2 }],
  },
  {
    start: 40.0,
    end: 56.6,
    hold: 4.4,
    lines: [{ file: "v5.m4a", text: "Command shift 6. Then just move the page.", at: 5.5, dur: 2.78 }],
  },
  {
    start: 61.4,
    end: 66.3,
    hold: 1.8,
    lines: [
      { file: "v6.m4a", text: "The words come with it.", at: 0.2, dur: 1.07 },
      { file: "v7.m4a", text: "They stay on this Mac.", at: 3.4, dur: 1.23 },
    ],
  },
  {
    start: 66.3,
    end: 69.9,
    hold: 5.2,
    lines: [{ file: "v8.m4a", text: "From the menu bar.", at: 0.5, dur: 1.0 }],
  },
];

const totalFrames = beats.reduce((sum, beat) => sum + sec(beat.end - beat.start) + sec(beat.hold), 0);

const screenStyle = {
  height: HEIGHT,
  width: Math.round(HEIGHT * (3584 / 2240)),
} as const;

const Screen: React.FC<{ trimBefore: number; trimAfter: number }> = ({ trimBefore, trimAfter }) => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#10202c", alignItems: "center", justifyContent: "center" }}>
      <Video src={staticFile("take.mp4")} trimBefore={trimBefore} trimAfter={trimAfter} muted style={screenStyle} />
    </AbsoluteFill>
  );
};

const Caption: React.FC<{ text: string }> = ({ text }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const opacity = interpolate(frame, [0, 8, durationInFrames - 8, durationInFrames], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });
  return (
    <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "flex-start", padding: "0 140px 78px" }}>
      <div
        style={{
          opacity,
          maxWidth: 980,
          color: "white",
          fontFamily: "Georgia, 'Iowan Old Style', serif",
          fontSize: 40,
          lineHeight: 1.25,
          textShadow: "0 2px 18px rgba(0,0,0,0.72)",
        }}
      >
        {text}
      </div>
    </AbsoluteFill>
  );
};

export const Walkover: React.FC = () => {
  let cursor = 0;
  const picture = beats.map((beat) => {
    const playFrames = sec(beat.end - beat.start);
    const holdFrames = sec(beat.hold);
    const from = cursor;
    cursor += playFrames + holdFrames;
    return { beat, from, playFrames, holdFrames };
  });

  return (
    <AbsoluteFill style={{ backgroundColor: "#10202c" }}>
      {picture.map(({ beat, from, playFrames, holdFrames }) => {
        const trimBefore = sec(beat.start);
        const trimAfter = sec(beat.end);
        return (
          <Sequence key={`${beat.start}-${beat.end}`} from={from} durationInFrames={playFrames + holdFrames}>
            <Sequence durationInFrames={playFrames}>
              <Screen trimBefore={trimBefore} trimAfter={trimAfter} />
            </Sequence>
            {holdFrames > 0 ? (
              <Sequence from={playFrames} durationInFrames={holdFrames}>
                <Freeze frame={0}>
                  <Screen trimBefore={trimAfter - 1} trimAfter={trimAfter} />
                </Freeze>
              </Sequence>
            ) : null}
            {beat.lines.map((line) => (
              <Sequence key={line.file} from={sec(line.at)} durationInFrames={sec(line.dur)}>
                <Audio src={staticFile(line.file)} />
                <Caption text={line.text} />
              </Sequence>
            ))}
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

export const MyComposition = () => {
  return (
    <Composition
      id="MyComp"
      component={Walkover}
      durationInFrames={totalFrames}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  );
};
