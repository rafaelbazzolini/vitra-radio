import 'models.dart';

const radioMoods = ['Treino', 'Trabalho', 'Meditação'];
const moodSuggestions = <String, List<RadioStation>>{
  'Treino': [
    RadioStation(
      id: 'mood-ffh-workout',
      name: 'FFH Workout',
      url: 'https://mp3.ffh.de/ffhchannels/hqworkout.mp3',
      genre: 'Dance · EDM',
      location: 'DE',
    ),
    RadioStation(
      id: 'mood-antenne-workout',
      name: 'ANTENNE BAYERN Workout Mix',
      url: 'https://stream.antenne.de/workout-hits/stream/mp3',
      genre: 'Dance · Pop',
      location: 'DE',
    ),
    RadioStation(
      id: 'mood-hotmix-workout',
      name: 'Hotmix Sport Workout',
      url: 'https://streaming.hotmixradio.com/hotmix-sport-plus-en-mp3',
      genre: 'Dance · Workout',
      location: 'FR',
    ),
  ],
  'Trabalho': [
    RadioStation(
      id: 'mood-groovesalad',
      name: 'SomaFM Groove Salad',
      url: 'https://ice2.somafm.com/groovesalad-128-mp3',
      genre: 'Ambient · Downtempo',
      location: 'US',
    ),
  ],
  'Meditação': [
    RadioStation(
      id: 'mood-dronezone',
      name: 'SomaFM Drone Zone',
      url: 'https://ice2.somafm.com/dronezone-128-mp3',
      genre: 'Ambient · Drone',
      location: 'US',
    ),
  ],
};
