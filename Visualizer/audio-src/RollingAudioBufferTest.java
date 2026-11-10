import java.util.Arrays;

public class RollingAudioBufferTest {
  private static void expect(RollingAudioBuffer buffer, float... expected) {
    float[] actual = new float[expected.length];
    buffer.copyTo(actual);
    if (!Arrays.equals(expected, actual)) {
      throw new AssertionError(Arrays.toString(actual) + " != " + Arrays.toString(expected));
    }
  }

  public static void main(String[] args) {
    RollingAudioBuffer buffer = new RollingAudioBuffer(4);
    expect(buffer, 0, 0, 0, 0);
    buffer.append(new float[] {1, 2}, 2, 1);
    expect(buffer, 0, 0, 1, 2);
    buffer.append(new float[] {2, 4, 4, 6, 6, 8}, 3, 2);
    expect(buffer, 2, 3, 5, 7);
    buffer.append(new float[] {10, 11, 12, 13, 14}, 5, 1);
    expect(buffer, 11, 12, 13, 14);
    try {
      buffer.append(new float[] {1}, 1, 2);
      throw new AssertionError("Invalid input accepted");
    } catch (IllegalArgumentException expected) { }
    System.out.println("RollingAudioBuffer tests passed");
  }
}
