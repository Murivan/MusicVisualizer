import java.io.IOException;

/** Backward-compatible Windows backend name. New code should use PortAudioInput. */
public final class WasapiInput extends PortAudioInput {
  public WasapiInput(String libraryPath) throws IOException {
    super(libraryPath);
  }
}
