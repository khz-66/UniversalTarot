import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.view.WindowManager;
import java.io.File;

PImage[] bilder;
int[] gezogeneKarten;
int anzahlGezogeneKarten = 0;
int maxKarten = 5;
boolean bildAngezeigt = false;
ArrayList<Integer> verfuegbareKarten;
int selectedCardIndex = -1;

SensorManager sensorManager;
Sensor accelerometer;
float accelX, accelY, accelZ;
float lastAccelX, lastAccelY, lastAccelZ;
float shakeThreshold = 10.0;
boolean shakeDetected = false;
int touchCount = 0;
long lastTouchTime = 0;
long doubleTapThreshold = 300;

boolean showNames = false;
String[] kartenBedeutungen;
boolean showMeaning = false;
long touchStartTime = 0;
long longPressThreshold = 500;
float touchStartX = 0;
float touchStartY = 0;
float moveTolerance = 90;
boolean isLongPressing = false;
long lastCardDrawTime = 0;
long cardDrawDebounceTime = 1000;
float lastTouchY = 0;
float touchScrollStartX = 0;
float touchScrollStartY = 0;
boolean isScrolling = false;
float scrollThreshold = 100;
float swipeThreshold = 100;
float topMargin;
float bottomMargin;

boolean showInstructions = false;
int count = 0;
String[] explanationText;

// Flag um zu prüfen, ob der Medienordner eigene Karten enthält
boolean externerOrdnerLeer = true;

void setup() {
  try {
    fullScreen();
  } catch (Exception e) {
    size(displayWidth, displayHeight);
    println("fullScreen() fehlgeschlagen, verwende size(): " + e.getMessage());
  }
  frameRate(5);
  imageMode(CENTER);
  textAlign(CENTER);

  topMargin = height * 0.2;
  bottomMargin = height - height * 0.2;

  // 1. Ziel-Verzeichnis auf dem externen Speicher bestimmen und ggf. erstellen
  File tarotDir = null;
  Context context = getActivity();
  if (context != null) {
    File[] mediaDirs = context.getExternalMediaDirs();
    if (mediaDirs != null && mediaDirs.length > 0 && mediaDirs[0] != null) {
      tarotDir = new File(mediaDirs[0], "Karten+Text");
    } else {
      tarotDir = new File(android.os.Environment.getExternalStoragePublicDirectory(
                          android.os.Environment.DIRECTORY_PICTURES), "Karten+Text");
    }

    if (!tarotDir.exists()) {
      boolean success = tarotDir.mkdirs();
      if (success) {
        println("Verzeichnis erstellt unter: " + tarotDir.getAbsolutePath());
      } else {
        println("Verzeichnis konnte nicht erstellt werden: " + tarotDir.getAbsolutePath());
      }
    }
  }

  // Wenn das Verzeichnis existiert, prüfe auf readme.txt und erstelle sie falls nicht vorhanden
  if (tarotDir != null && tarotDir.exists()) {
    File readmeFile = new File(tarotDir, "readme.txt");
    if (!readmeFile.exists()) {
      String[] readmeInhalt = {
        "Hier können eigene Bilddateien (bis zu 100 Karten von karte1.png bis karte100.png und eine Kartenrückseite back.png) abgelegt werden. (jpg einfach in png umbenennen :-)",
        "",
        "Standard-Reihenfolge für Tarot",
        "karte1 bis karte22: Große Arcana",
        "karte23 bis karte36: Stäbe",
        "karte37 bis karte50: Kelche",
        "karte51 bis karte64: Schwerter",
        "karte65 bis karte78: Münzen",
        "",
        "Die Kartennummern müssen fortlaufend sein!",      
        "", 
        "In die Datei bedeutung.txt können der Reihe nach beliebige Texte eingetragen werden, die für die jeweilige Karte eingeblendet werden können.",
        "",
        "Die Einträge in bedeutung.txt müssen jeweils durch eine Zeile mit ### getrennt werden.",
        "",
        "Ist keine bedeutung.txt vorhanden, werden die Standardtexte eingeblendet."
      };
      saveStrings(readmeFile.getAbsolutePath(), readmeInhalt);
      println("readme.txt wurde erfolgreich im Verzeichnis Karten+Text erstellt.");
    }
  }

  // 2. Erklärungstext direkt aus dem Standard-Array nutzen
  explanationText = new String[] {
    "Schütteln: Eine Karte ziehen.",
    "Lang drücken: Bedeutung.",
    "Nach oben/unten wischen: Blättern.",
    "Nach links wischen: Reset."
  };

  // 3. Kartenbilder laden
  bilder = new PImage[101]; // max. 100 Karten + back.png

  // Vorab prüfen, ob überhaupt eine externe Karte existiert
  boolean hatExterneKarten = false;
  for (int i = 1; i < bilder.length; i++) {
    String dateiName = "karte" + i + ".png";
    if (tarotDir != null && tarotDir.exists()) {
      File datei = new File(tarotDir, dateiName);
      if (datei.exists()) {
        hatExterneKarten = true;
        break;
      }
    }
  }

  // Flag für die Warnanzeige setzen
  externerOrdnerLeer = !hatExterneKarten;

  // Rückseite laden: Sucht erst extern, falls nicht da, automatisch intern aus data
  bilder[0] = loadCardImage(tarotDir, "back.png");

  // Schleife für die Karten 1 bis 100
  for (int i = 1; i < bilder.length; i++) {
    String dateiName = "karte" + i + ".png";

    if (hatExterneKarten) {
      // Wenn der externe Ordner eigene Karten hat: NUR von dort laden!
      if (tarotDir != null && tarotDir.exists()) {
        File datei = new File(tarotDir, dateiName);
        if (datei.exists()) {
          bilder[i] = loadImage(datei.getAbsolutePath());
        } else {
          bilder[i] = null; // Fehlende Karten werden NICHT aus data ergänzt
          println("Externe Karte fehlt: " + dateiName + " (wird übersprungen)");
        }
      }
    } else {
      // Wenn KEINE einzige externe Karte existiert: Nutze komplett den data-Ordner
      bilder[i] = loadImage(dateiName);
      if (bilder[i] == null) {
        println("Kritischer Fehler: Interne " + dateiName + " fehlt im data-Ordner!");
      }
    }
  }

  // 4. Karten-Bedeutungen laden (auch bei abweichender Kartenzahl)
  String[] fullMeaningText = null;
  File bedeutungenFile = (tarotDir != null) ? new File(tarotDir, "bedeutung.txt") : null;
  if (bedeutungenFile != null && bedeutungenFile.exists()) {
    fullMeaningText = loadStrings(bedeutungenFile.getAbsolutePath());
  }
  if (fullMeaningText == null || fullMeaningText.length == 0) {
    fullMeaningText = loadStrings("bedeutung.txt");
  }

  if (fullMeaningText != null && fullMeaningText.length > 0) {
    String combinedText = join(fullMeaningText, "\n");
    String[] rawMeanings = split(combinedText, "###");
    ArrayList<String> cleaned = new ArrayList<String>();
    for (int i = 0; i < rawMeanings.length; i++) {
      String eintrag = rawMeanings[i].trim();
      if (eintrag.length() > 0) {
        cleaned.add(eintrag);
      }
    }
    if (cleaned.size() > 0 && cleaned.size() <= bilder.length - 1) {
      kartenBedeutungen = cleaned.toArray(new String[cleaned.size()]);
      println("Bedeutungen geladen: " + kartenBedeutungen.length);
    } else {
      kartenBedeutungen = null;
      println("bedeutung.txt ungültig oder zu viele Einträge: " + cleaned.size());
    }
  } else {
    kartenBedeutungen = null;
    println("Keine bedeutung.txt gefunden.");
  }

  // 5. Logik-Initialisierungen (Zustand & Sensoren)
  gezogeneKarten = new int[maxKarten];
  verfuegbareKarten = new ArrayList<Integer>();
  rebuildAvailableCards();

  try {
    loadState();
  } catch (Exception e) {
    println("Fehler beim Laden des Zustands: " + e.getMessage());
  }

  // Sensor-Initialisierung
  try {
    if (context == null) return;
    sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
    if (sensorManager == null) return;
    accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
    if (accelerometer == null) return;
    sensorManager.registerListener(sensorListener, accelerometer, SensorManager.SENSOR_DELAY_NORMAL);
  } catch (Exception e) {
    println("Fehler bei Sensor-Initialisierung: " + e.getMessage());
  }
}

void rebuildAvailableCards() {
  verfuegbareKarten.clear();
  for (int i = 1; i < bilder.length; i++) {
    if (bilder[i] != null) {
      verfuegbareKarten.add(i);
    }
  }
}

PImage loadCardImage(File dir, String dateiName) {
  PImage img = null;
  if (dir != null && dir.exists()) {
    File datei = new File(dir, dateiName);
    if (datei.exists()) {
      img = loadImage(datei.getAbsolutePath());
    }
  }
  if (img == null) {
    img = loadImage(dateiName);
    if (img == null) {
      println("Kritischer Fehler: " + dateiName + " konnte weder extern noch intern geladen werden!");
    }
  }
  return img;
}

void draw() {
  background(0);
  try {
    if (getActivity() != null) {
      getActivity().runOnUiThread(new Runnable() {
        @Override
        public void run() {
          if (bildAngezeigt) {
            getActivity().getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
          } else {
            getActivity().getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
          }
        }
      });
    }
  } catch (Exception e) {
    println("Fehler bei FLAG_KEEP_SCREEN_ON: " + e.getMessage());
  }

  boolean isLandscape = displayWidth > displayHeight;

  if (bildAngezeigt && anzahlGezogeneKarten > 0) {
    count = 0;
    showInstructions = false;

    if (anzahlGezogeneKarten == 1) {
      if (bilder[gezogeneKarten[0]] != null) {
        float scale = min(width / float(bilder[gezogeneKarten[0]].width), height / float(bilder[gezogeneKarten[0]].height));
        float skalierteBreite = bilder[gezogeneKarten[0]].width * scale;
        float skalierteHoehe = bilder[gezogeneKarten[0]].height * scale;
        image(bilder[gezogeneKarten[0]], width / 2, height / 2, skalierteBreite, skalierteHoehe);

        int meaningIdx = gezogeneKarten[0] - 1;
        if (showMeaning && kartenBedeutungen != null && meaningIdx >= 0 && meaningIdx < kartenBedeutungen.length) {
          String meaningText = kartenBedeutungen[meaningIdx];
          float textSizeVal = isLandscape ? max(skalierteBreite * 0.06, 25) : max(skalierteBreite * 0.06, 25);
          textSize(textSizeVal);
          float textMargin = skalierteBreite * 0.08;
          float textDrawWidth = skalierteBreite - 2 * textMargin;
          float cardXLeft = width / 2 - skalierteBreite / 2;
          float cardYTop = height / 2 - skalierteHoehe / 2;

          fill(0, 100);
          rect(cardXLeft, cardYTop, skalierteBreite, skalierteHoehe);
          fill(255);
          textAlign(LEFT, TOP);

          float textYStart = cardYTop + textMargin;
          text(meaningText, cardXLeft + textMargin, textYStart, textDrawWidth, skalierteHoehe - 2 * textMargin);
          textAlign(CENTER, CENTER);
        }
      }
    } else {
      float kartenBreite = width / (float(anzahlGezogeneKarten) + 0.5);
      float scale = min(kartenBreite / float(bilder[0].width), height / float(bilder[0].height));
      float skalierteBreite = bilder[0].width * scale;
      float skalierteHoehe = bilder[0].height * scale;
      float startX = (width - anzahlGezogeneKarten * skalierteBreite) / 2;

      for (int i = 0; i < anzahlGezogeneKarten; i++) {
        if (bilder[gezogeneKarten[i]] != null) {
          float xPos = startX + i * skalierteBreite + skalierteBreite / 2;
          image(bilder[gezogeneKarten[i]], xPos, height / 2, skalierteBreite, skalierteHoehe);

          int meaningIdx = gezogeneKarten[i] - 1;
          if (showMeaning && kartenBedeutungen != null && meaningIdx >= 0 && meaningIdx < kartenBedeutungen.length) {
            String meaningText = kartenBedeutungen[meaningIdx];
            float textSizeVal = isLandscape ? max(skalierteBreite * 0.06, 25) : max(skalierteBreite * 0.06, 25);
            textSize(textSizeVal);
            float textMargin = skalierteBreite * 0.08;
            float textDrawWidth = skalierteBreite - 2 * textMargin;
            float cardXLeft = xPos - skalierteBreite / 2;
            float cardYTop = height / 2 - skalierteHoehe / 2;

            fill(0, 100);
            rect(cardXLeft, cardYTop, skalierteBreite, skalierteHoehe);
            fill(255);
            textAlign(LEFT, TOP);

            float textYStart = cardYTop + textMargin;
            text(meaningText, cardXLeft + textMargin, textYStart, textDrawWidth, skalierteHoehe - 2 * textMargin);
            textAlign(CENTER, CENTER);
          }
        }
      }
    }
  } else {
    if (bilder[0] != null) {
      float scale = min(width / float(bilder[0].width), height / float(bilder[0].height));
      float skalierteBreite = bilder[0].width * scale;
      float skalierteHoehe = bilder[0].height * scale;
      image(bilder[0], width / 2, height / 2, skalierteBreite, skalierteHoehe);

      // Wenn der externe Ordner leer ist, zeige die Meldung DAUERHAFT oberhalb der Karte an
      if (externerOrdnerLeer) {
        float textGroesse = min(width, height) * 0.035;
        textSize(textGroesse);
        fill(255, 60, 60);
        textAlign(CENTER, BOTTOM);

        float kartenOberkante = (height / 2) - (skalierteHoehe / 2);
        float abstand = 25;
        float nachrichtY = kartenOberkante - abstand;

        text("Eigene Karten und bedeutung.txt in android/media/universal.tarot/Karten+Text/ eintragen.",
             20, nachrichtY - 120, width - 40, 120);
      }

      showInstructions = false;
      if (count <= 40) {
        count++;
        showInstructions = true;
      }

      if (showInstructions) {
        textSize(min(width, height) * 0.04);
        fill(250);
        textAlign(CENTER, BOTTOM);
        float textY = height - 20;
        float lineHeight = min(width, height) * 0.05;

        for (int i = 0; i < explanationText.length; i++) {
          text(explanationText[i], width / 2, textY - (explanationText.length - 1 - i) * lineHeight);
        }
      }
    } else {
      fill(255);
      textSize(width * 0.05);
      text("Schüttle das Gerät oder scrolle, um eine Karte zu ziehen", width / 2, height / 2);
    }
  }
}

void touchStarted() {
  if (touches.length == 1) {
    float touchX = touches[0].x;
    float touchY = touches[0].y;
    long currentTime = millis();

    touchStartTime = currentTime;
    touchStartX = touchX;
    touchStartY = touchY;
    isLongPressing = true;

    if (touchY > topMargin && touchY < bottomMargin && millis() - lastCardDrawTime > cardDrawDebounceTime) {
      if (currentTime - lastTouchTime < doubleTapThreshold) {
        touchCount++;
        if (touchCount >= 2) {
          touchCount = 0;
          return;
        }
      } else {
        touchCount = 1;
      }

      touchScrollStartY = touchY;
      touchScrollStartX = touchX;
      isScrolling = false;

      if (!bildAngezeigt) {
        float scale = min(width / float(bilder[0].width), height / float(bilder[0].height));
        float skalierteBreite = bilder[0].width * scale;
        float left = width / 2 - skalierteBreite / 2;
        float right = width / 2 + skalierteBreite / 2;
        if (touchX >= left && touchX <= right) {
          selectedCardIndex = 0;
        } else {
          selectedCardIndex = -1;
        }
      } else if (anzahlGezogeneKarten > 0) {
        if (anzahlGezogeneKarten == 1) {
          float scale = min(width / float(bilder[gezogeneKarten[0]].width), height / float(bilder[gezogeneKarten[0]].height));
          float skalierteBreite = bilder[gezogeneKarten[0]].width * scale;
          float left = width / 2 - skalierteBreite / 2;
          float right = width / 2 + skalierteBreite / 2;
          if (touchX >= left && touchX <= right) {
            selectedCardIndex = 0;
          } else {
            selectedCardIndex = -1;
          }
        } else {
          float kartenBreite = width / (float(anzahlGezogeneKarten) + 0.5);
          float scale = min(kartenBreite / float(bilder[0].width), height / float(bilder[0].height));
          float skalierteBreite = bilder[0].width * scale;
          float startX = (width - anzahlGezogeneKarten * skalierteBreite) / 2;
          selectedCardIndex = -1;
          for (int i = 0; i < anzahlGezogeneKarten; i++) {
            float xPos = startX + i * skalierteBreite;
            if (touchX >= xPos && touchX < xPos + skalierteBreite) {
              selectedCardIndex = i;
              break;
            }
          }
        }
      }
    }
    lastTouchTime = currentTime;
  }
}

void touchMoved() {
  if (touches.length == 1) {
    float currentY = touches[0].y;
    float currentX = touches[0].x;
    if (isLongPressing) {
      float distance = dist(touchStartX, touchStartY, currentX, currentY);
      if (distance > moveTolerance) {
        isLongPressing = false;
      }
    }

    if (touchScrollStartY > topMargin && touchScrollStartY < bottomMargin && currentY > topMargin && currentY < bottomMargin) {
      float deltaY = currentY - touchScrollStartY;
      float deltaX = currentX - touchScrollStartX;

      if (abs(deltaY) > scrollThreshold && selectedCardIndex >= 0) {
        isScrolling = true;
        if (!bildAngezeigt && selectedCardIndex == 0) {
          if (deltaY < 0 && !verfuegbareKarten.isEmpty()) {
            int index = 1;
            gezogeneKarten[0] = verfuegbareKarten.get(index);
            verfuegbareKarten.remove(index);
            anzahlGezogeneKarten = 1;
            bildAngezeigt = true;
            selectedCardIndex = 0;
            lastCardDrawTime = millis();
            try {
              saveState();
            } catch (Exception e) {}
          }
        } else if (bildAngezeigt && anzahlGezogeneKarten > 0) {
          int newCardIndex = gezogeneKarten[selectedCardIndex];
          if (deltaY > 0) {
            // Nach unten scrollen: Kartennummer verringern
            if (newCardIndex > 1) {
              newCardIndex--;
              gezogeneKarten[selectedCardIndex] = newCardIndex;
            } else if (newCardIndex == 1) {
              bildAngezeigt = false;
              anzahlGezogeneKarten = 0;
              verfuegbareKarten.add(gezogeneKarten[selectedCardIndex]);
              gezogeneKarten[selectedCardIndex] = 0;
            }
          } else {
            // Nach oben scrollen: Kartennummer ERHÖHEN mit Sicherheitsbegrenzung
            int maxVerfuegbareKarte = 0;
            if (externerOrdnerLeer) {
              maxVerfuegbareKarte = bilder.length - 1;
            } else {
              for (int i = 1; i < bilder.length; i++) {
                if (bilder[i] != null) {
                  maxVerfuegbareKarte = i;
                }
              }
            }

            if (newCardIndex < maxVerfuegbareKarte) {
              newCardIndex++;
              if (bilder[newCardIndex] != null) {
                gezogeneKarten[selectedCardIndex] = newCardIndex;
              }
            }
          }
          try {
            saveState();
          } catch (Exception e) {}
        }
        touchScrollStartY = currentY;
      } else if (!isScrolling && abs(deltaY) < scrollThreshold / 2) {
        if (deltaX > swipeThreshold) {
          showNames = !showNames;
          try {
            saveState();
          } catch (Exception e) {}
          touchScrollStartX = currentX;
          return;
        }
        if (deltaX < -swipeThreshold) {
          bildAngezeigt = false;
          anzahlGezogeneKarten = 0;
          rebuildAvailableCards();
          selectedCardIndex = -1;
          showNames = false;
          try {
            saveState();
          } catch (Exception e) {}
          return;
        }
      }
      lastTouchY = currentY;
    }
  }
}

void touchEnded() {
  if (touches.length <= 1) {
    long touchDuration = millis() - touchStartTime;
    if (isLongPressing && touchDuration >= longPressThreshold) {
      showMeaning = !showMeaning;
      try {
        saveState();
      } catch (Exception e) {}
    }
    isLongPressing = false;
    if (isScrolling) {
      touchCount = 0;
      isScrolling = false;
    }
  }
}

SensorEventListener sensorListener = new SensorEventListener() {
  @Override
  public void onSensorChanged(SensorEvent event) {
    if (event.sensor.getType() == Sensor.TYPE_ACCELEROMETER && millis() - lastCardDrawTime > cardDrawDebounceTime) {
      accelX = event.values[0];
      accelY = event.values[1];
      accelZ = event.values[2];
      float deltaX = abs(accelX - lastAccelX);
      float deltaY = abs(accelY - lastAccelY);
      float deltaZ = abs(accelZ - lastAccelZ);

      if (deltaX > shakeThreshold || deltaY > shakeThreshold) {
        if (!shakeDetected) {
          shakeDetected = true;
          if (anzahlGezogeneKarten >= maxKarten) {
            anzahlGezogeneKarten = 0;
            rebuildAvailableCards();
            selectedCardIndex = -1;
            showNames = false;
          }

          int gezogeneNr = 0;
          PImage gewaehltesBild = null;
          while (!verfuegbareKarten.isEmpty() && gewaehltesBild == null) {
            int index = int(random(verfuegbareKarten.size()));
            gezogeneNr = verfuegbareKarten.get(index);
            verfuegbareKarten.remove(index);
            gewaehltesBild = bilder[gezogeneNr];
          }

          if (gewaehltesBild != null) {
            gezogeneKarten[anzahlGezogeneKarten] = gezogeneNr;
            anzahlGezogeneKarten++;
            bildAngezeigt = true;
            selectedCardIndex = -1;
            lastCardDrawTime = millis();
            try {
              saveState();
            } catch (Exception e) {}
          }
        }
      } else {
        shakeDetected = false;
      }
      lastAccelX = accelX;
      lastAccelY = accelY;
      lastAccelZ = accelZ;
    }
  }

  @Override
  public void onAccuracyChanged(Sensor sensor, int accuracy) {}
};

void saveState() {
  try {
    String[] state = new String[maxKarten + 3];
    state[0] = String.valueOf(bildAngezeigt);
    state[1] = String.valueOf(anzahlGezogeneKarten);
    state[2] = String.valueOf(showNames);
    for (int i = 0; i < maxKarten; i++) {
      state[i + 3] = String.valueOf(gezogeneKarten[i]);
    }
    saveStrings(getActivity().getFilesDir() + "/state.txt", state);

    String[] available = new String[verfuegbareKarten.size()];
    for (int i = 0; i < verfuegbareKarten.size(); i++) {
      available[i] = String.valueOf(verfuegbareKarten.get(i));
    }
    saveStrings(getActivity().getFilesDir() + "/available.txt", available);
  } catch (Exception e) {}
}

void loadState() {
  try {
    String[] state = loadStrings(getActivity().getFilesDir() + "/state.txt");
    if (state != null && state.length >= maxKarten + 3) {
      bildAngezeigt = Boolean.valueOf(state[0]);
      anzahlGezogeneKarten = Integer.valueOf(state[1]);
      showNames = Boolean.valueOf(state[2]);

      // 1. Obergrenze f����r den aktuellen App-Start ermitteln
      int maxVerfuegbareKarte = 0;
      if (externerOrdnerLeer) {
        maxVerfuegbareKarte = bilder.length - 1; // 100
      } else {
        for (int i = 1; i < bilder.length; i++) {
          if (bilder[i] != null) {
            maxVerfuegbareKarte = i;
          }
        }
      }

      // 2. Gezogene Karten laden und sofort auf das aktuelle Maximum begrenzen
      for (int i = 0; i < maxKarten; i++) {
        int geladenerIndex = Integer.valueOf(state[i + 3]);

        if (geladenerIndex > maxVerfuegbareKarte) {
          gezogeneKarten[i] = maxVerfuegbareKarte;
        } else {
          gezogeneKarten[i] = geladenerIndex;
        }

        // Zusätzlicher Schutz: Falls die Karte genau null (nicht geladen) ist
        if (bildAngezeigt && gezogeneKarten[i] > 0 && bilder[gezogeneKarten[i]] == null) {
          gezogeneKarten[i] = 0;
          anzahlGezogeneKarten = 0;
          bildAngezeigt = false;
        }
      }

      String[] available = loadStrings(getActivity().getFilesDir() + "/available.txt");
      if (available != null) {
        verfuegbareKarten.clear();
        for (String s : available) {
          int verfuegbareKarte = Integer.valueOf(s);
          if (verfuegbareKarte <= maxVerfuegbareKarte && (externerOrdnerLeer || bilder[verfuegbareKarte] != null)) {
            verfuegbareKarten.add(verfuegbareKarte);
          }
        }
      }
    }
  } catch (Exception e) {
    println("Fehler beim Bereinigen des geladenen Zustands: " + e.getMessage());
  }
}

void onPause() {
  super.onPause();
  try {
    if (sensorManager != null) {
      sensorManager.unregisterListener(sensorListener);
    }
    if (getActivity() != null) {
      getActivity().runOnUiThread(new Runnable() {
        @Override
        public void run() {
          getActivity().getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
      });
    }
    saveState();
  } catch (Exception e) {}
}

void onResume() {
  super.onResume();
  try {
    if (sensorManager != null && accelerometer != null) {
      sensorManager.registerListener(sensorListener, accelerometer, SensorManager.SENSOR_DELAY_NORMAL);
    }
    if (getActivity() != null && bildAngezeigt) {
      getActivity().runOnUiThread(new Runnable() {
        @Override
        public void run() {
          getActivity().getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
      });
    }
    loadState();
  } catch (Exception e) {}
}
