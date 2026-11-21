# FieldKit Movement Arcade

A Windows arcade controlled by a XIAO nRF52840 Sense attached to a glove. Connect it directly to a PC with a USB-C data cable. Audio hardware and extra sensors are optional and the games work offline.

## Choose a movement

Open **Launch FieldKit.cmd** from the extracted app folder. Select an injury or practice context on the front page, then select an exercise already cleared by your therapist. The context explains what to check with your clinician. It does not assign a treatment plan. For a demo, choose **Demo or general practice**.

| Game | Movement | How to play |
|---|---|---|
| Asteroid Blaster | Multi-direction coordination | Move the reticle onto an asteroid and hold until the laser fires. |
| Backwater Ferry | Side-to-side wrist motion | Steer to a dock, hold, then return to center. |
| Lantern Lift | Wrist bend or straighten | Raise the light into a lantern, hold, then return to center. |
| Reef Rescue | Forearm rotation | Turn the hand to swim to a crystal, hold to collect it, then return to center. |

## Connect and calibrate

1. Close Arduino Serial Monitor and older FieldKit windows. Select the glove COM port and click **Connect** if the app has not already connected. This test PC used **COM26**.
2. For **Asteroid Blaster**, set **Center**, **Left**, **Right**, **Up**, and **Down**, returning to center between captures. Hold still during each capture.
3. For a **single-movement game**, capture **Center**, then use the **Right** calibration button to capture the endpoint of the chosen motion. This endpoint can be upward, sideways, or a turn. Recapture these two poses when you change movement or direction.
4. Choose a daily target size and a hold time that suits the planned session. Select **Start round**. Select **End round** to finish early. There is no countdown.
5. Open **Therapy progress** from the front page or arcade to view dated game rounds. Progress stays on this PC. The report shows game activity and does not measure joint recovery.

Select **Keyboard preview** to try any game with the arrow keys. Use **Home** on the keyboard to return the aiming cursor to center. Preview rounds are excluded from the progress log.

## Movement references

- [Cambridge University Hospitals: hand therapy active wrist exercises](https://www.cuh.nhs.uk/patient-information/hand-therapy-active-wrist-exercises/)
- [Dudley Group NHS Foundation Trust: wrist sprain and soft-tissue injury](https://www.dgft.nhs.uk/pil/soft-tissue-injury-sprain-wrist/)
- [Distal Radius Fracture Rehabilitation clinical practice guideline](https://doi.org/10.2519/jospt.2024.0301)
- [NHS: hand tendon repair and recovery](https://www.nhs.uk/tests-and-treatments/hand-tendon-repair/)

These sources describe the movement categories. FieldKit is an interactive prototype and has not been clinically validated. The single glove sensor responds to glove orientation and does not distinguish individual finger movement or measure joint angles directly.

## Firmware

The test board was already flashed. For another Sense board, upload **firmware/FieldKitMotionTest/FieldKitMotionTest.ino** from Arduino IDE. Select **Seeed XIAO nRF52840 Sense** and its COM port. The sketch sends timestamped X/Y/Z acceleration over USB serial at 115200 baud. There is no new firmware requirement if the previous FieldKit build worked with your glove.
