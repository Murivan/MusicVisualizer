import java.util.Locale;

/** Sustained non-silent input test for the shared PortAudio backend. */
public final class PortAudioLiveInputTest {
  public static void main(String[] args) throws Exception {
    if (args.length < 3 || args.length > 6) {
      throw new IllegalArgumentException(
          "Expected library path, host API fragment, device fragment, optional seconds, read frames, and FFT size");
    }
    int seconds = args.length > 3 ? Integer.parseInt(args[3]) : 10;
    int readFrames = args.length > 4 ? Integer.parseInt(args[4]) : 128;
    int fftSize = args.length > 5 ? Integer.parseInt(args[5]) : 512;
    if (seconds <= 0 || readFrames <= 0 || fftSize <= 0) {
      throw new IllegalArgumentException("Capture duration and buffer sizes must be positive");
    }

    try (PortAudioInput input = new PortAudioInput(args[0])) {
      String[] devices = input.allDevices();
      String[] hosts = input.allHostApis();
      int[] hostTypes = input.allHostTypes();
      int selected = -1;
      for (int i = 0; i < devices.length; i++) {
        if (hosts[i].toLowerCase(Locale.ROOT).contains(args[1].toLowerCase(Locale.ROOT))
            && devices[i].toLowerCase(Locale.ROOT).contains(args[2].toLowerCase(Locale.ROOT))) {
          if (selected >= 0) throw new IllegalArgumentException("Input name matches multiple devices");
          selected = i;
        }
      }
      if (selected < 0) throw new IllegalArgumentException("PortAudio input not found: " + args[1] + " / " + args[2]);

      System.out.println("Opening " + hosts[selected] + " / " + devices[selected]);
      System.out.flush();
      input.openAny(selected, readFrames, fftSize, false);
      System.out.printf(Locale.ROOT, "Stream started: %.0f Hz, %d channel(s), %.2f ms reported input latency%n",
          input.sampleRate(), input.channels(), input.inputLatencyMs());
      System.out.flush();
      long deadline = System.nanoTime() + seconds * 1_000_000_000L;
      long previousBlock = 0;
      while (System.nanoTime() < deadline) {
        String failure = input.error();
        if (!failure.isEmpty()) throw new IllegalStateException(failure);
        long currentBlock = input.lastBlockNanos();
        if (currentBlock != 0 && currentBlock != previousBlock) previousBlock = currentBlock;
        else if (System.nanoTime() - (previousBlock == 0 ? deadline - seconds * 1_000_000_000L : previousBlock)
            > 3_000_000_000L) {
          throw new IllegalStateException("PortAudio capture made no block progress for three seconds");
        }
        Thread.sleep(25);
      }

      float[] samples = new float[fftSize];
      input.snapshot(samples);
      double squareSum = 0;
      float peak = 0;
      for (float sample : samples) {
        if (!Float.isFinite(sample)) throw new IllegalStateException("Capture returned a non-finite sample");
        squareSum += sample * sample;
        peak = Math.max(peak, Math.abs(sample));
      }
      if (input.blocks() == 0 || peak <= 0.0001f) {
        throw new IllegalStateException("Capture did not produce a non-silent audio signal");
      }
      System.out.printf(Locale.ROOT,
          "%s / %s: %.0f Hz, %d channel(s), %d-frame reads, %.2f ms reported input latency, "
              + "%d blocks, %.2f ms mean interval, %d overflows, final-window RMS %.6f peak %.6f%n",
          hosts[selected], devices[selected], input.sampleRate(), input.channels(), input.readFrames(),
          input.inputLatencyMs(), input.blocks(), input.intervalMs(), input.overflows(),
          Math.sqrt(squareSum / samples.length), peak);
      if (input.overflows() != 0) throw new IllegalStateException("Capture reported input overflows");
    }
  }
}
