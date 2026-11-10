/** A synchronized, zero-padded mono window of the most recent audio frames. */
public final class RollingAudioBuffer {
  private final float[] samples;
  private int next;

  public RollingAudioBuffer(int length) {
    if (length <= 0) throw new IllegalArgumentException("Window length must be positive");
    samples = new float[length];
  }

  public synchronized void append(float[] interleaved, int frames, int channels) {
    if (channels <= 0 || frames < 0 || (long) frames * channels > interleaved.length) {
      throw new IllegalArgumentException("Invalid audio block dimensions");
    }
    for (int i = 0; i < frames; i++) {
      float sum = 0;
      for (int channel = 0; channel < channels; channel++) {
        sum += interleaved[i * channels + channel];
      }
      samples[next] = sum / channels;
      next = (next + 1) % samples.length;
    }
  }

  public synchronized void copyTo(float[] output) {
    if (output.length != samples.length) throw new IllegalArgumentException("Wrong window length");
    System.arraycopy(samples, next, output, 0, samples.length - next);
    System.arraycopy(samples, 0, output, samples.length - next, next);
  }
}
