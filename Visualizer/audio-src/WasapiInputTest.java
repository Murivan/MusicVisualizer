/** Verifies capture-stall boundaries and the Windows PortAudio 19.7 WASAPI layout. */
public class WasapiInputTest {
  public static void main(String[] args) {
    if (WasapiInput.isCaptureStalled(2999, 0, 3000)
        || !WasapiInput.isCaptureStalled(3000, 0, 3000)
        || WasapiInput.isCaptureStalled(4000, 2000, 3000)) {
      throw new AssertionError("Incorrect stall detection");
    }
    if (com.sun.jna.Platform.isWindows() && com.sun.jna.Native.POINTER_SIZE == 8) {
      WasapiInput.WasapiStreamInfo info = new WasapiInput.WasapiStreamInfo(false);
      info.write();
      if (info.size() != 56 || info.getPointer().getInt(0) != 56
          || info.getPointer().getInt(4) != 13 || info.getPointer().getInt(8) != 1
          || info.getPointer().getInt(12) != 1) {
        throw new AssertionError("Unexpected WASAPI stream info layout");
      }
      WasapiInput.WasapiStreamInfo polling = new WasapiInput.WasapiStreamInfo(true);
      polling.write();
      if (polling.getPointer().getInt(12) != 9) throw new AssertionError("Incorrect polling flags");
    }
    System.out.println("WASAPI stall and native layout tests passed");
  }
}
