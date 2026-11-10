import ddf.minim.AudioBuffer;
import ddf.minim.analysis.FFT;

/** Compares a rolling stereo window against Minim's existing FFT input path. */
public class AudioAnalysisTest {
  public static void main(String[] args) {
    int size = 512;
    float[] interleaved = new float[size * 2];
    float[] mono = new float[size];
    for (int i = 0; i < size; i++) {
      float sample = (float) Math.sin(2 * Math.PI * 8 * i / size);
      interleaved[2 * i] = sample;
      interleaved[2 * i + 1] = sample * 0.5f;
      mono[i] = sample * 0.75f;
    }
    RollingAudioBuffer ring = new RollingAudioBuffer(size);
    ring.append(interleaved, size, 2);
    float[] snapshot = new float[size];
    ring.copyTo(snapshot);
    FFT rolling = new FFT(size, 48000);
    FFT legacy = new FFT(size, 48000);
    rolling.forward(snapshot);
    legacy.forward(new AudioBuffer() {
      public int size() { return mono.length; }
      public float get(int i) { return mono[i]; }
      public float[] toArray() { return mono.clone(); }
      public float level() {
        float squared = 0;
        for (float sample : mono) squared += sample * sample;
        return (float) Math.sqrt(squared / mono.length);
      }
    });
    for (int bin = 0; bin < size / 2; bin++) {
      if (Math.abs(rolling.getBand(bin) - legacy.getBand(bin)) > 0.0001f) {
        throw new AssertionError("FFT mismatch at bin " + bin);
      }
    }
    if (rolling.getBand(8) < 190) throw new AssertionError("Expected signal peak at bin 8");
    System.out.println("FFT parity test passed");
  }
}
