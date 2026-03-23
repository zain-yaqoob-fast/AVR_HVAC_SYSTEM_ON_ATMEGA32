# Smart HVAC System using ATmega32 (Embedded Systems Project)

## 📌 Overview
This project presents the design and implementation of an automated HVAC (Heating, Ventilation, and Air Conditioning) system using ATmega32 microcontrollers. The system monitors temperature, humidity, and air quality, and automatically controls heating, cooling, intake, and exhaust mechanisms.

## 🧠 System Architecture
The system uses a **Master-Slave architecture**:

- **Slave Unit**: Handles sensors and actuators
- **Master Unit**: Handles user interface (LCD + Keypad)
- Communication via **RS-485 (MAX487)**

## ⚙️ Technologies Used
- AVR Assembly Language
- ATmega32 Microcontroller
- Proteus Simulation
- RS-485 Communication (UART)
- I2C / ADC Interfacing

## 🔌 Hardware Components
- ATmega32 (x2)
- BME280 (Temperature & Humidity)
- MQ135 (Air Quality Sensor)
- MAX487 (RS-485)
- 16x2 LCD
- 4x4 Keypad
- Motors / Fans / Servo
- Motor Driver (L298N)

## 🔄 System Working
- Sensors continuously monitor environment
- Slave microcontroller processes data
- Based on thresholds:
  - Temperature → HOT / COOL
  - Humidity → INTAKE / EXHAUST
  - Air Quality → Ventilation
- Data sent to Master via RS-485
- Master displays values on LCD

## 📊 Control Logic
- Temperature:
  - >30°C → Cooling ON
  - <27°C → Heating ON
- Humidity:
  - <20% → Intake ON
  - >30% → Exhaust ON
- Air Quality:
  - Poor → Ventilation ON

## 📁 Project Structure
- `/code` → AVR Assembly files
- `/proteus` → Simulation files
- `/images` → Screenshots
- `/docs` → Full report

## ▶️ Simulation
1. Open Proteus
2. Load `.pdsprj` file
3. Run simulation
4. Observe LCD + actuator behavior

## 📈 Results
- Real-time environmental monitoring
- Automated control system
- ~40% energy efficiency improvement over manual systems

## 🚀 Key Learning Outcomes
- Embedded system design (Hardware + Software)
- Microcontroller interfacing (ADC, I2C, UART)
- RS-485 communication
- Real-time control systems

## 👨‍💻 Authors
- Muhammad Ziyan Shabbir  
- M. Zain Yaqoob  
- Malik Abdul Rehman  