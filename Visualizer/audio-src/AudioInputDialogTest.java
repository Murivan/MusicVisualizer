import java.awt.Component;
import java.awt.Container;
import java.awt.Window;
import java.awt.event.WindowEvent;
import java.util.ArrayList;
import java.util.List;
import javax.swing.JComboBox;
import javax.swing.JDialog;
import javax.swing.JOptionPane;
import javax.swing.Timer;
import javax.swing.JLabel;

public class AudioInputDialogTest {
  private static void collect(Container parent, Class<?> type, List<Component> result) {
    for (Component child : parent.getComponents()) {
      if (type.isInstance(child)) result.add(child);
      if (child instanceof Container) collect((Container) child, type, result);
    }
  }

  private static void checkSizes(JComboBox<?> choices, int maximum) {
    if (choices.isEditable()) throw new AssertionError("Buffer dropdown must not be editable");
    int index = 0;
    for (int size = 32; size <= maximum; size *= 2) {
      if (index >= choices.getItemCount() || !Integer.valueOf(size).equals(choices.getItemAt(index++)))
        throw new AssertionError("Incorrect buffer choices");
    }
    if (index != choices.getItemCount()) throw new AssertionError("Unexpected buffer choice");
  }

  private static void test(Visualizer sketch, int driverIndex, int deviceIndex, int modeIndex, int action) {
    final Throwable[] error = new Throwable[1];
    Timer timer = new Timer(250, event -> {
      for (Window window : Window.getWindows()) {
        if (!(window instanceof JDialog) || !window.isShowing()
            || !((JDialog) window).getTitle().equals("Audio Input Selection")) continue;
        ((Timer) event.getSource()).stop();
        try {
          List<Component> controls = new ArrayList<>();
          collect((Container) window, JComboBox.class, controls);
          if (controls.size() != 5) throw new AssertionError("Expected five dropdowns");
          JComboBox<?> drivers = (JComboBox<?>) controls.get(0);
          JComboBox<?> devices = (JComboBox<?>) controls.get(1);
          JComboBox<?> modes = (JComboBox<?>) controls.get(2);
          JComboBox<?> capture = (JComboBox<?>) controls.get(3);
          JComboBox<?> audio = (JComboBox<?>) controls.get(4);
          checkSizes(capture, 8192);
          checkSizes(audio, 65536);
          drivers.setSelectedIndex(driverIndex);
          devices.setSelectedIndex(deviceIndex);
          if (modes.isEnabled() != (driverIndex == 1)) throw new AssertionError("Wrong mode availability");
          modes.setSelectedIndex(modeIndex);
          if (!Integer.valueOf(256).equals(capture.getSelectedItem())
              || !Integer.valueOf(512).equals(audio.getSelectedItem()))
            throw new AssertionError("Incorrect buffer defaults");
          if (capture.isEnabled() != (driverIndex != 0)) throw new AssertionError("Wrong capture field availability");
          if (driverIndex != 0) capture.setSelectedItem(128);
          audio.setSelectedItem(1024);
          if (action == -1) window.dispatchEvent(new WindowEvent(window, WindowEvent.WINDOW_CLOSING));
          else {
            List<Component> panes = new ArrayList<>();
            collect((Container) window, JOptionPane.class, panes);
            ((JOptionPane) panes.get(0)).setValue(action);
          }
        } catch (Throwable failure) {
          error[0] = failure;
          window.dispose();
        }
        return;
      }
    });
    timer.start();
    Visualizer.InputChoice choice = sketch.promptForLiveInput(
        new String[] {"Java A", "Java B"},
        new String[] {"WAS A", "ASIO A", "WAS B"},
        new String[] {"WASAPI", "ASIO", "WASAPI"},
        new int[] {13, 3, 13}, "");
    timer.stop();
    if (error[0] != null) throw new AssertionError(error[0]);
    if (sketch.audioBufferSize != 512 || sketch.captureBufferSize != 256)
      throw new AssertionError("Dialog changed buffer defaults before applying choice");
    if (action != JOptionPane.OK_OPTION) {
      if (choice != null) throw new AssertionError("Cancellation returned a selection");
    } else {
      int expected = driverIndex == 0 ? deviceIndex : driverIndex == 1 ? (deviceIndex == 0 ? 0 : 2) : 1;
      if (choice == null || choice.portAudio != (driverIndex != 0) || choice.deviceIndex != expected
          || !choice.mode.equals(driverIndex == 1 && modeIndex == 1 ? "exclusive" : "shared")
          || choice.audioFrames != 1024 || choice.captureFrames != (driverIndex == 0 ? 256 : 128)) {
        throw new AssertionError("Wrong selection");
      }
    }
  }

  private static void testNonPowerDefault(Visualizer sketch, boolean javaSound) {
    final Throwable[] error = new Throwable[1];
    final int[] step = {0};
    sketch.captureBufferSize = 300;
    Timer timer = new Timer(250, event -> {
      for (Window window : Window.getWindows()) {
        if (!(window instanceof JDialog) || !window.isShowing()
            || !((JDialog) window).getTitle().equals("Audio Input Selection")) continue;
        try {
          List<Component> controls = new ArrayList<>();
          collect((Container) window, JComboBox.class, controls);
          List<Component> labels = new ArrayList<>();
          collect((Container) window, JLabel.class, labels);
          List<Component> panes = new ArrayList<>();
          collect((Container) window, JOptionPane.class, panes);
          JComboBox<?> driver = (JComboBox<?>)controls.get(0);
          JComboBox<?> capture = (JComboBox<?>)controls.get(3);
          if (step[0] == 0) {
            if (capture.getSelectedIndex() != -1) throw new AssertionError("Non-power default selected");
            boolean shown = false;
            for (Component label : labels) {
              String text = ((JLabel)label).getText();
              if (text != null && text.contains("300") && text.contains("select a size")) shown = true;
            }
            if (!shown) throw new AssertionError("Invalid default message not displayed");
            driver.setSelectedIndex(javaSound ? 0 : 1);
            if (javaSound) ((Timer)event.getSource()).stop();
          } else {
            boolean shown = false;
            for (Component label : labels) {
              String text = ((JLabel)label).getText();
              if (text != null && text.contains("Select an available buffer size")) shown = true;
            }
            if (!shown) throw new AssertionError("Validation message not displayed");
            capture.setSelectedItem(64);
            ((Timer)event.getSource()).stop();
          }
          step[0]++;
          ((JOptionPane)panes.get(0)).setValue(JOptionPane.OK_OPTION);
        } catch (Throwable failure) {
          error[0] = failure;
          ((Timer)event.getSource()).stop();
          window.dispose();
        }
        return;
      }
    });
    timer.start();
    Visualizer.InputChoice result = sketch.promptForLiveInput(new String[] {"Java"},
        new String[] {"WAS"}, new String[] {"WASAPI"}, new int[] {13}, "");
    timer.stop();
    if (error[0] != null) throw new AssertionError(error[0]);
    if (step[0] != (javaSound ? 1 : 2) || result == null
        || result.captureFrames != (javaSound ? 300 : 64) || result.audioFrames != 512
        || sketch.captureBufferSize != 300)
      throw new AssertionError("Non-power default handling failed");
    sketch.captureBufferSize = 256;
  }

  public static void main(String[] args) {
    Visualizer sketch = new Visualizer();
    sketch.audioBufferSize = 512;
    sketch.captureBufferSize = 256;
    test(sketch, 0, 1, 0, JOptionPane.OK_OPTION);
    test(sketch, 1, 1, 1, JOptionPane.OK_OPTION);
    test(sketch, 2, 0, 1, JOptionPane.OK_OPTION);
    test(sketch, 1, 0, 0, JOptionPane.CANCEL_OPTION);
    test(sketch, 0, 0, 0, -1);
    testNonPowerDefault(sketch, false);
    testNonPowerDefault(sketch, true);
    System.out.println("Audio input dialog tests passed");
    System.exit(0);
  }
}
