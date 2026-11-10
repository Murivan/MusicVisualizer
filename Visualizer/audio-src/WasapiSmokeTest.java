import java.util.Locale;

/** Hardware test: DLL path, unique device-name fragment, optional duration, frames and mode. */
public class WasapiSmokeTest {
  public static void main(String[] args) throws Exception {
    if (args.length < 2 || args.length > 5) {
      throw new IllegalArgumentException("Expected DLL path, device name, optional seconds, capture frames and mode");
    }
    int seconds = args.length >= 3 ? Integer.parseInt(args[2]) : 2;
    int frames = args.length >= 4 ? Integer.parseInt(args[3]) : 128;
    String mode = args.length >= 5 ? args[4] : "shared";
    if (!mode.equals("shared") && !mode.equals("exclusive") && !mode.equals("exclusive-polling"))
      throw new IllegalArgumentException("Invalid WASAPI mode");
    if (seconds < 1 || seconds > 3600 || frames < 32 || frames > 8192) {
      throw new IllegalArgumentException("Seconds must be 1-3600 and capture frames 32-8192");
    }
    try (WasapiInput input = new WasapiInput(args[0])) {
      String[] devices = input.devices();
      int selected = -1;
      for (int i = 0; i < devices.length; i++) {
        if (devices[i].toLowerCase(Locale.ROOT).contains(args[1].toLowerCase(Locale.ROOT))) {
          if (selected >= 0) throw new IllegalArgumentException("Device name matches multiple inputs: " + args[1]);
          selected = i;
        }
      }
      if (selected < 0) throw new IllegalArgumentException("WASAPI device not found: " + args[1]);
      input.open(selected, frames, 512, !mode.equals("shared"), mode.equals("exclusive-polling"));
      System.out.println("Opened " + mode + " " + devices[selected] + ", " + input.sampleRate()
          + " Hz, host-reported input latency " + input.inputLatencyMs() + " ms");
      long start = System.nanoTime();
      long deadline = start + seconds * 1_000_000_000L;
      long timeout = Math.max(3_000_000_000L,
          (long) Math.ceil(4.0 * frames * 1_000_000_000.0 / input.sampleRate()));
      while (System.nanoTime() < deadline) {
        Thread.sleep(100);
        if (!input.error().isEmpty()) throw new IllegalStateException(input.error());
        long latest = input.lastBlockNanos();
        long reference = latest == 0 ? start : latest;
        if (System.nanoTime() - reference > timeout) {
          throw new IllegalStateException("Capture stalled for more than " + timeout / 1_000_000L
              + " ms after "
              + input.blocks() + " blocks (" + input.overflows() + " overflows)");
        }
      }
      if (!input.error().isEmpty()) throw new IllegalStateException(input.error());
      if (input.blocks() < 5) throw new IllegalStateException("Too few capture blocks: " + input.blocks());
      if (input.overflows() != 0) throw new IllegalStateException("Input overflows: " + input.overflows());
      float[] snapshot = new float[512];
      input.snapshot(snapshot);
      for (float sample : snapshot) {
        if (!Float.isFinite(sample)) throw new IllegalStateException("Invalid audio sample");
      }
      System.out.println(mode + " " + devices[selected] + ": " + input.sampleRate() + " Hz, " + input.channels()
          + " channels, " + frames + " frames, " + seconds + " seconds");
      System.out.println(input.blocks() + " blocks, " + input.overflows() + " overflows, "
          + input.intervalMs() + " ms smoothed interval, " + input.jitterMs() + " ms smoothed deviation");
      System.out.println(input.inputLatencyMs() + " ms host-reported input latency (not end-to-end)");
    }
  }
}
