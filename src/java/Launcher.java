import com.sun.javafx.application.PlatformImpl;
import com.sun.javafx.stage.StageHelper;
import java.io.File;
import java.util.Arrays;
import java.util.jar.JarFile;
import javafx.application.Platform;
import javafx.collections.ListChangeListener;
import javafx.stage.Stage;

// Starts the official launcher (the Main-Class of SWGLegendsLauncher.exe) unchanged,
// in the same JVM as the app's own macOS menus (native, Resources/java/libswglmenus.dylib).
//
// JavaFX names the app menu items ("Hide …", "Quit …") after the application class,
// which would read "launcher.Main"; the first name set wins, so claim it before the
// launcher starts.
//
//   java -Dswgl.res=<Resources> -Dswgl.game=<game folder> \
//        -cp <Resources>/java:SWGLegendsLauncher.exe \
//        Launcher SWGLegendsLauncher.exe
public class Launcher {
  private static final String RES = System.getProperty("swgl.res", ".");
  private static final String GAME = System.getProperty("swgl.game", System.getProperty("user.dir"));

  private static native boolean installMenus(String resources, String gameFolder);

  public static void main(String[] args) throws Exception {
    String mainClass;
    try (JarFile jar = new JarFile(args[0])) {
      mainClass = jar.getManifest().getMainAttributes().getValue("Main-Class");
    }
    PlatformImpl.startup(() -> {
      com.sun.glass.ui.Application.GetApplication().setName("Launcher");
      try {
        System.load(new File(RES, "java/libswglmenus.dylib").getAbsolutePath());
        installMenusWithNextWindow();
      } catch (Throwable t) {
        System.err.println("SWGL on Mac: menus unavailable: " + t);
      }
    });
    String[] rest = Arrays.copyOfRange(args, 1, args.length);
    Class.forName(mainClass).getMethod("main", String[].class).invoke(null, (Object) rest);
  }

  // JavaFX creates the macOS main menu along with its first window.
  private static void installMenusWithNextWindow() {
    StageHelper.getStages().addListener(new ListChangeListener<Stage>() {
      @Override public void onChanged(Change<? extends Stage> change) {
        StageHelper.getStages().removeListener(this);
        Platform.runLater(() -> {
          if (!installMenus(RES, GAME))
            installMenusWithNextWindow();
        });
      }
    });
  }
}
