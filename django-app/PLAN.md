# План Django-приложения

Приложение слушает порт 80 на `innerlogistics.lovethosetrains.com`. Прокси `polylogistics.lovethosetrains.com` (`212.67.30.137`) в это приложение не входит: он пересылает запрос на внешний порт 7023, а тот попадает на порт 80.

У MatSim, SUMO и Webots по одному экземпляру. Пока экземпляр занят, заявки ждут в его приоритетной очереди. Порядок в очереди задает `request_timestamp`: раньше полученный запрос идет раньше. В очереди нет файлов. Видео и xml пишутся на диск в каталог прогона, а очередь хранит только пару, по которой эти файлы находятся.

`team_dir` — имя `.osm` без расширения (`team1.osm` → `team1`). `request_timestamp` — время, когда Django принял запрос.

Каталог прогона — `team_dir`/`request_timestamp`. Туда сразу кладется `.osm`. Дальше в этот же каталог дописываются результаты шагов.

```
team1/
  20261030-132600/
    team1.osm
    matsim.mp4       # после MatSim
    plans.xml
    sumo.mp4         # после SUMO
    objects.xml
    webots.mp4       # после Webots
  result0.zip        # архив прогона, лежит в team_dir
  result1.zip
```

## Очереди

Четыре приоритетные очереди. Элемент любой из них — пара `request_timestamp`, `team_dir`. Этого достаточно, чтобы прочитать `.osm`, `plans.xml` и `objects.xml` из `team_dir`/`request_timestamp`.

- Очередь MatSim. Заявка принята, MatSim еще не брал ее.
- Очередь SUMO. MatSim записал `matsim.mp4` и `plans.xml`.
- Очередь Webots. SUMO записал `sumo.mp4` и `objects.xml`.
- Очередь Zip. Прогон закончен: либо все три шага прошли, либо один из них упал. Zip собирает каталог прогона как есть.

Упавший MatSim не попадает в очередь SUMO. Упавший SUMO не попадает в очередь Webots. Оба попадают в Zip. Webots после своего шага попадает в Zip и при успехе, и при сбое.

Пока экземпляр обрабатывает заявку, пара хранится в переменных этого экземпляра, не в очереди:

- `matsim_current_request_timestamp`, `matsim_current_team_dir`
- `sumo_current_request_timestamp`, `sumo_current_team_dir`
- `webots_current_request_timestamp`, `webots_current_team_dir`

Экземпляр свободен, когда эти переменные пусты. Освободился — забирает следующий элемент своей очереди и снова заполняет переменные.

## POST с файлом .osm

Команда отправляет файл `.osm`. Ответ `200` уходит сразу, не дожидаясь симуляторов.

1. Запомнить `request_timestamp`. Положить файл в `team_dir`/`request_timestamp`. Положить в очередь MatSim пару `request_timestamp`, `team_dir`. Ответить `200`.
2. MatSim свободен и очередь не пуста. Забрать пару, записать ее в `matsim_current_request_timestamp` и `matsim_current_team_dir`. Отдать в MatSim `.osm` из этого каталога.
3. MatSim записал `matsim.mp4` и `plans.xml` в `matsim_current_team_dir`/`matsim_current_request_timestamp`. Пару положить в очередь SUMO. Если MatSim не обработал заявку, пару положить в очередь Zip, а не в SUMO. Очистить переменные MatSim. MatSim свободен и может взять следующую заявку. SUMO, когда заберет пару, читает `.osm` и `plans.xml` из `team_dir`/`request_timestamp` и держит пару в `sumo_current_request_timestamp`, `sumo_current_team_dir`.
4. SUMO записал `sumo.mp4` и `objects.xml` в каталог своей текущей пары. Пару положить в очередь Webots. Если SUMO не обработал заявку, пару положить в очередь Zip, а не в Webots. Очистить переменные SUMO. Webots читает `.osm` и `objects.xml` из каталога и держит пару в `webots_current_request_timestamp`, `webots_current_team_dir`.
5. Webots записал `webots.mp4` в каталог своей текущей пары и кладет пару в очередь Zip. Если Webots не обработал заявку, пара все равно кладется в очередь Zip. Очистить переменные Webots.
6. Zip забирает пару, собирает содержимое `team_dir`/`request_timestamp` в архив и кладет его в `team_dir` под именем `result{n}.zip`. `{n}` — сколько `.zip` уже лежит в `team_dir` на момент создания. Первый архив команды — `result0.zip`.

Три симулятора работают параллельно над разными заявками. У каждого в работе не больше одной пары.

## Второй GET

В запросе приходит `team_dir` строкой, не файлом.

Ответ — файл `result{n}.zip` с наибольшим `{n}` среди архивов в этом каталоге. Имена `.zip` читаются из `team_dir`, сортируются, отдается последнее имя в этом порядке. Если `.zip` нет, ответ `404`.

## Моки

Контейнеров MatSim, SUMO и Webots еще нет. Вместо них три мока. Они читают вход из `team_dir`/`request_timestamp` и пишут выход туда же.

- MatSim читает `.osm`, пишет `matsim.mp4` и `plans.xml`.
- SUMO читает `.osm` и `plans.xml`, пишет `sumo.mp4` и `objects.xml`.
- Webots читает `.osm` и `objects.xml`, пишет `webots.mp4`.

Сбой задается только в тестах. Мок этого шага не пишет свои файлы и возвращает ошибку. Воркер тогда кладет пару в Zip по правилам шага.

Один процесс Django и четыре воркера (три симулятора и Zip). Очереди в памяти этого процесса: экземпляров симуляторов по одному, несколько процессов растащили бы очереди.

## Тесты

1. Все шаги успешны. POST отвечает `200`. В каталоге прогона есть `.osm`, три `.mp4`, `plans.xml`, `objects.xml`. В `team_dir` появляется `result0.zip` с этими файлами. Второй GET возвращает этот архив.
2. Сбой MatSim. В каталоге прогона только `.osm`. В очереди SUMO пары нет. Zip собирает архив без видео и xml. Второй GET отдает его.
3. Сбой SUMO. Есть `matsim.mp4` и `plans.xml`. Нет `sumo.mp4`, `objects.xml`, `webots.mp4`. В очереди Webots пары нет. Архив содержит то, что успел MatSim.
4. Сбой Webots. Есть результаты MatSim и SUMO, нет `webots.mp4`. Пара все равно доходит до Zip.
5. Две заявки. Вторая не входит в MatSim, пока первая не освободила его. Более ранний `request_timestamp` забирается раньше. У каждой команды свой `result0.zip`. Повторный прогон той же команды дает `result1.zip`, второй GET отдает его как последнее имя в сортировке.
6. Второй GET по `team_dir` без архивов отвечает `404`.

## Из чего собрать

```
django-app/
  PLAN.md
  config/             # порт 80, один процесс
  pipeline/
    views.py          # POST с .osm и GET result{n}.zip
    storage.py        # team_dir, request_timestamp, result{n}.zip
    queues.py         # четыре приоритетные очереди и текущие пары экземпляров
    mocks.py          # MatSim, SUMO, Webots
    tests.py
```

Настоящие контейнеры потом подставляются вместо моков. Очереди по-прежнему несут только `request_timestamp` и `team_dir`, файлы по-прежнему пишутся в каталог прогона.
