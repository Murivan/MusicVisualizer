import com.sun.jna.Native;
import com.sun.jna.NativeLong;

/** Verifies the PortAudio structures used by both supported 64-bit ABIs. */
public final class PortAudioInputLayoutTest {
  public static void main(String[] args) {
    boolean windows = System.getProperty("os.name").startsWith("Windows");
    boolean macOS = System.getProperty("os.name").startsWith("Mac");
    if ((!windows && !macOS) || Native.POINTER_SIZE != 8) {
      throw new IllegalStateException("Expected 64-bit Windows or macOS");
    }
    if (NativeLong.SIZE != (windows ? 4 : 8)) {
      throw new AssertionError("Unexpected C long size: " + NativeLong.SIZE);
    }
    expect("PaHostApiInfo", new PortAudioInput.HostInfo().size(), 32);
    expect("PaDeviceInfo", new PortAudioInput.DeviceInfo().size(), 72);
    expect("PaStreamParameters", new PortAudioInput.StreamParameters().size(), 32);
    expect("PaStreamInfo", new PortAudioInput.StreamInfo().size(), 32);
    if (windows) {
      PortAudioInput.WasapiStreamInfo info = new PortAudioInput.WasapiStreamInfo(false);
      info.write();
      expect("PaWasapiStreamInfo", info.size(), 56);
      expect("PaWasapiStreamInfo.size", info.getPointer().getInt(0), 56);
      expect("PaWasapiStreamInfo.hostApiType", info.getPointer().getInt(4), 13);
      expect("PaWasapiStreamInfo.version", info.getPointer().getInt(8), 1);
      expect("PaWasapiStreamInfo.flags", info.getPointer().getInt(12), 1);
    }
    System.out.println("PortAudio native structure layouts passed");
  }

  private static void expect(String name, int actual, int expected) {
    if (actual != expected) {
      throw new AssertionError(name + " size/value was " + actual + "; expected " + expected);
    }
  }
}
