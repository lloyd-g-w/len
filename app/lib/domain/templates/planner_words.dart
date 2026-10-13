import 'planner_calendar.dart';

/// The fixed words printed on planner pages, in one [PlannerLanguage]
/// (sentence case; headings are drawn in capitals). [week] holds `#` for
/// the week number.
typedef PlannerWords = ({
  String week,
  String schedule,
  String priorities,
  String toDo,
  String notes,
});

/// [PlannerWords] for every [PlannerLanguage].
const Map<PlannerLanguage, PlannerWords> plannerWords = {
  PlannerLanguage.enGB: _en,
  PlannerLanguage.enUS: _en,
  PlannerLanguage.cs: (
    week: 'Týden #',
    schedule: 'Rozvrh',
    priorities: 'Priority',
    toDo: 'Úkoly',
    notes: 'Poznámky',
  ),
  PlannerLanguage.da: (
    week: 'Uge #',
    schedule: 'Tidsplan',
    priorities: 'Prioriteter',
    toDo: 'Opgaver',
    notes: 'Noter',
  ),
  PlannerLanguage.de: (
    week: 'Woche #',
    schedule: 'Zeitplan',
    priorities: 'Prioritäten',
    toDo: 'Aufgaben',
    notes: 'Notizen',
  ),
  PlannerLanguage.es: (
    week: 'Semana #',
    schedule: 'Horario',
    priorities: 'Prioridades',
    toDo: 'Tareas',
    notes: 'Notas',
  ),
  PlannerLanguage.fr: (
    week: 'Semaine #',
    schedule: 'Planning',
    priorities: 'Priorités',
    toDo: 'À faire',
    notes: 'Notes',
  ),
  PlannerLanguage.it: (
    week: 'Settimana #',
    schedule: 'Programma',
    priorities: 'Priorità',
    toDo: 'Da fare',
    notes: 'Note',
  ),
  PlannerLanguage.nl: (
    week: 'Week #',
    schedule: 'Planning',
    priorities: 'Prioriteiten',
    toDo: 'Te doen',
    notes: 'Notities',
  ),
  PlannerLanguage.nb: (
    week: 'Uke #',
    schedule: 'Timeplan',
    priorities: 'Prioriteringer',
    toDo: 'Gjøremål',
    notes: 'Notater',
  ),
  PlannerLanguage.pl: (
    week: 'Tydzień #',
    schedule: 'Harmonogram',
    priorities: 'Priorytety',
    toDo: 'Do zrobienia',
    notes: 'Notatki',
  ),
  PlannerLanguage.ptBR: (
    week: 'Semana #',
    schedule: 'Agenda',
    priorities: 'Prioridades',
    toDo: 'Tarefas',
    notes: 'Anotações',
  ),
  PlannerLanguage.ptPT: (
    week: 'Semana #',
    schedule: 'Agenda',
    priorities: 'Prioridades',
    toDo: 'Tarefas',
    notes: 'Notas',
  ),
  PlannerLanguage.fi: (
    week: 'Viikko #',
    schedule: 'Aikataulu',
    priorities: 'Prioriteetit',
    toDo: 'Tehtävät',
    notes: 'Muistiinpanot',
  ),
  PlannerLanguage.sv: (
    week: 'Vecka #',
    schedule: 'Schema',
    priorities: 'Prioriteringar',
    toDo: 'Att göra',
    notes: 'Anteckningar',
  ),
  PlannerLanguage.tr: (
    week: '#. Hafta',
    schedule: 'Program',
    priorities: 'Öncelikler',
    toDo: 'Yapılacaklar',
    notes: 'Notlar',
  ),
  PlannerLanguage.el: (
    week: 'Εβδομάδα #',
    schedule: 'Πρόγραμμα',
    priorities: 'Προτεραιότητες',
    toDo: 'Εργασίες',
    notes: 'Σημειώσεις',
  ),
  PlannerLanguage.ru: (
    week: 'Неделя #',
    schedule: 'Расписание',
    priorities: 'Приоритеты',
    toDo: 'Задачи',
    notes: 'Заметки',
  ),
  PlannerLanguage.uk: (
    week: 'Тиждень #',
    schedule: 'Розклад',
    priorities: 'Пріоритети',
    toDo: 'Завдання',
    notes: 'Нотатки',
  ),
};

const PlannerWords _en = (
  week: 'Week #',
  schedule: 'Schedule',
  priorities: 'Priorities',
  toDo: 'To do',
  notes: 'Notes',
);
