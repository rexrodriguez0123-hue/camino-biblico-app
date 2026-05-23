import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../main.dart';
import '../widgets/success_popup.dart';
import '../widgets/error_popup.dart';
import '../widgets/game_over_popup.dart';
import '../widgets/no_hearts_popup.dart';

// Enum para rastrear qué popup está abierto
enum OpenPopupType {
  none,
  success,
  error,
  noHearts,
  gameOver,
}

class PracticeScreen extends StatefulWidget {
  final int lessonId;
  const PracticeScreen({super.key, required this.lessonId});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  bool _isLoading = true;
  List<dynamic> _exercises = [];
  int _currentIndex = 0;
  
  // Audio service for feedback sounds
  final AudioService _audioService = AudioService();
  
  // Para evitar repeticiones infinitas
  final Set<int> _repeatedExerciseIds = {};
  
  // State for current question
  bool _answered = false;
  dynamic _selectedOption; // String for cloze/selection, List<String> for scramble
  TextEditingController _textController = TextEditingController(); // For type-in/cloze
  bool _isCorrect = false;

  // Tracking for stats
  int _correctCount = 0;
  int _totalAttempted = 0;
  OpenPopupType _currentPopupType = OpenPopupType.none; // Rastrear qué popup está abierto

  @override
  void initState() {
    super.initState();
    _fetchLessonData();
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _fetchLessonData() async {
    final api = context.read<ApiService>();
    final data = await api.getLessonDetails(widget.lessonId);
    
    // Flatten exercises from verses
    List<dynamic> allExercises = [];
    if (data['verses'] != null) {
      for (var verse in data['verses']) {
        if (verse['exercises'] != null) {
          allExercises.addAll(verse['exercises']);
        }
      }
    }

    // Limit to 10 exercises per session for playability
    if (allExercises.length > 10) {
      allExercises.shuffle();
      allExercises = allExercises.sublist(0, 10);
    }

    if (mounted) {
      setState(() {
        _exercises = allExercises;
        _isLoading = false;
      });
    }
  }

  void _checkAnswer(dynamic answer) {
    if (_answered) return;

    final currentExercise = _exercises[_currentIndex];
    final type = currentExercise['exercise_type'];
    final answerData = currentExercise['answer_data'];
    
    bool correctGuess = false;

    switch (type) {
      case 'cloze':
        final correct = answerData['correct'] ?? '';
        correctGuess = answer.toString().toLowerCase().trim() == correct.toString().toLowerCase().trim();
        break;

      case 'selection':
        final correct = answerData['correct'] ?? '';
        correctGuess = answer.toString() == correct.toString();
        break;

      case 'type_in':
        final correct = answerData['correct'] ?? '';
        final acceptList = answerData['accept'] as List? ?? [];
        final userAnswer = (answer ?? _textController.text).toString().trim().toLowerCase();
        correctGuess = userAnswer == correct.toString().toLowerCase().trim()
            || acceptList.any((a) => a.toString().toLowerCase().trim() == userAnswer);
        break;

      case 'scramble':
        final correctOrder = List<String>.from(answerData['correct_order'] ?? []);
        final userList = answer is List ? answer.map((e) => e?.toString() ?? '').toList() : <String>[];
        correctGuess = userList.join(' ') == correctOrder.join(' ');
        break;

      case 'true_false':
        final correct = answerData['correct'];
        if (correct is bool) {
          correctGuess = answer == correct;
        } else {
          correctGuess = answer.toString() == correct.toString();
        }
        break;

      default:
        correctGuess = false;
    }

    final isRepeat = currentExercise['is_repeat'] == true;

    if (!isRepeat) {
      _totalAttempted++;
      if (correctGuess) _correctCount++;
    }

    setState(() {
      _answered = true;
      _isCorrect = correctGuess;
      _selectedOption = answer;
    });

    // Enviar al backend solo si es el primer intento
    if (!isRepeat) {
      _submitToBackend(currentExercise, correctGuess);
    }

    // Calcular corazones restantes inmediatamente (antes de la respuesta async)
    final userState = context.read<UserState>();
    int remainingHearts = userState.hearts;
    if (!correctGuess && !isRepeat && remainingHearts > 0) {
      remainingHearts -= 1;

      // Actualizar el estado INMEDIATAMENTE sin esperar al backend
      userState.updateStats(hearts: remainingHearts);

      // Agregar el ejercicio al final de la cola para repetir
      final exerciseId = currentExercise['id'];
      if (!_repeatedExerciseIds.contains(exerciseId)) {
        _repeatedExerciseIds.add(exerciseId);
        final repeatedExercise = Map<String, dynamic>.from(currentExercise);
        repeatedExercise['is_repeat'] = true;
        _exercises.add(repeatedExercise);
      }
    }

    // Provide feedback
    if (correctGuess) {
      // Play correct sound
      _audioService.playCorrectSound();
      
      setState(() => _currentPopupType = OpenPopupType.success);
      
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.6),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (dialogContext, anim1, anim2) {
          return PopScope(
            canPop: false,
            child: SuccessPopup(
              onNext: () {
                setState(() => _currentPopupType = OpenPopupType.none);
                Navigator.pop(dialogContext); // Close dialog
                _nextQuestion();        // Go to next
              },
            ),
          );
        },
        transitionBuilder: (context, anim1, anim2, child) {
          return FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(
                parent: anim1,
                curve: Curves.easeOutBack,
              )),
              child: child,
            ),
          );
        },
      );
    } else {
      // Play incorrect sound
      _audioService.playIncorrectSound();
      
      // Si se acabaron los corazones, mostrar popup especial
      if (remainingHearts == 0) {
        setState(() => _currentPopupType = OpenPopupType.noHearts);
        
        // Capturar contexto del scaffold ANTES de mostrar el dialog
        final screenContext = context;
        
        showGeneralDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(0.6),
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (dialogContext, anim1, anim2) {
            return PopScope(
              canPop: false,
              child: NoHeartsPopup(
                timeUntilRegeneration: _calculateTimeUntilRegen(),
                onRecharge: () {
                  setState(() => _currentPopupType = OpenPopupType.none);
                  Navigator.pop(dialogContext);
                  Navigator.pushNamed(screenContext, '/shop');
                },
                onGoHome: () {
                  setState(() => _currentPopupType = OpenPopupType.none);
                  Navigator.pop(dialogContext);
                  Navigator.pushNamedAndRemoveUntil(screenContext, '/dashboard', (route) => false);
                },
              ),
            );
          },
          transitionBuilder: (context, anim1, anim2, child) {
            return FadeTransition(
              opacity: anim1,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(
                  parent: anim1,
                  curve: Curves.easeOutBack,
                )),
                child: child,
              ),
            );
          },
        );
      } else {
        // Mostrar popup de error normal si aún hay corazones
        setState(() => _currentPopupType = OpenPopupType.error);
        
        // Capturar contexto del scaffold ANTES de mostrar el dialog
        final screenContext = context;
        
        showGeneralDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(0.6),
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (dialogContext, anim1, anim2) {
            String correctText = 'Respuesta';
            if (type == 'true_false') {
              correctText = answerData['correct'] == true ? 'Verdadero' : 'Falso';
              if (answerData['explanation'] != null) {
                correctText += '\n(${answerData['explanation']})';
              }
            } else {
              correctText = answerData['correct']?.toString() ?? answerData['correct_order']?.join(' ') ?? 'Respuesta';
            }

            return PopScope(
              canPop: false,
              child: ErrorPopup(
                correctAnswer: correctText,
                remainingHearts: remainingHearts,
                onNext: () {
                  setState(() => _currentPopupType = OpenPopupType.none);
                  Navigator.pop(dialogContext);
                  _nextQuestion();
                },
              ),
            );
          },
          transitionBuilder: (context, anim1, anim2, child) {
            return FadeTransition(
              opacity: anim1,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(
                  parent: anim1,
                  curve: Curves.easeOutBack,
                )),
                child: child,
              ),
            );
          },
        );
      }
    }
  }

  // Calcular tiempo hasta la próxima regeneración de corazón
  String _calculateTimeUntilRegen() {
    final userState = context.read<UserState>();
    final lastRegenStr = userState.lastHeartRegen;
    
    if (lastRegenStr == null) {
      return '4:00:00'; // Default si no hay fecha
    }
    
    try {
      final lastRegen = DateTime.parse(lastRegenStr);
      final nextRegen = lastRegen.add(const Duration(hours: 4));
      final now = DateTime.now();
      
      if (now.isAfter(nextRegen)) {
        return '0:00:00'; // Ya se regeneró
      }
      
      final diff = nextRegen.difference(now);
      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      final seconds = diff.inSeconds.remainder(60);
      
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } catch (e) {
      return '4:00:00';
    }
  }

  // Back button del celular está completamente deshabilitado
  // El usuario solo puede avanzar con los botones del popup

  Future<void> _submitToBackend(Map<String, dynamic> exercise, bool isCorrect) async {
    try {
      final api = context.read<ApiService>();
      final exerciseId = exercise['id'];
      if (exerciseId == null) return; // Offline fallback exercise

      final result = await api.submitAnswer(
        exerciseId: exerciseId,
        isCorrect: isCorrect,
      );

      // Update user stats
      if (mounted) {
        final userState = context.read<UserState>();
        userState.updateStats(
          hearts: result['hearts'],
          gems: result['gems'],
          streak: result['streak_days'],
          totalXp: result['total_xp'],
        );
      }
    } catch (e) {
      // Silently fail — offline mode or auth issue
      debugPrint('Failed to submit answer: $e');
    }
  }

  void _nextQuestion() {
    if (_currentIndex < _exercises.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _selectedOption = null;
        _textController.clear();
      });
    } else {
      _finishLesson();
    }
  }

  void _finishLesson() {
    setState(() => _currentPopupType = OpenPopupType.gameOver);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: GameOverPopup(
          correctCount: _correctCount,
          totalAttempted: _totalAttempted,
          gemsEarned: _correctCount * 2, // Gana 2 gemas por respuesta correcta
          onNext: () {
            setState(() => _currentPopupType = OpenPopupType.none);
            Navigator.pop(ctx); // Cerrar popup
            // Navegar a /dashboard asegurando que existe la ruta
            Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Práctica')),
        body: const Center(child: Text('No hay ejercicios en esta lección.')),
      );
    }

    final exercise = _exercises[_currentIndex];
    final type = exercise['exercise_type'];
    final questionData = exercise['question_data'];
    
    // Progress
    double progress = (_currentIndex + 1) / _exercises.length;

    return PopScope(
      canPop: false, // Deshabilitar botón back del celular
      onPopInvokedWithResult: (didPop, result) {
        // Back button o gesto de retroceso detectado pero bloqueado
        debugPrint('Back button bloqueado en PracticeScreen');
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false, // No mostrar botón back automático
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              // Navegar a /dashboard en lugar de solo pop (que causa pantalla negra)
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
            },
          ),
          title: LinearProgressIndicator(value: progress, minHeight: 10, borderRadius: BorderRadius.circular(5)),
        ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             const SizedBox(height: 20),
             Text(
               'Pregunta ${_currentIndex + 1} de ${_exercises.length}', 
               style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
               textAlign: TextAlign.center,
             ),
             const SizedBox(height: 10),
             _buildExerciseTypeLabel(type),
             const SizedBox(height: 20),
             
             // --- EXERCISE CONTENT ---
             Expanded(child: SingleChildScrollView(child: _buildExerciseContent(type, questionData, exercise))),
             
             const SizedBox(height: 10),

             // Check Button (for type_in, cloze, and scramble)
             if (!_answered && (type == 'type_in' || type == 'cloze' || type == 'scramble'))
               ElevatedButton(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.green,
                   padding: const EdgeInsets.symmetric(vertical: 15)
                 ),
                 onPressed: () => _checkAnswer((type == 'type_in' || type == 'cloze') ? _textController.text : _selectedOption),
                 child: const Text('Comprobar', style: TextStyle(fontSize: 18, color: Colors.white)),
               ),
               
             // Continue Button removed since dialog handles progression
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildExerciseTypeLabel(String type) {
    String label;
    IconData icon;
    switch (type) {
      case 'cloze':
        label = 'Completa el versículo';
        icon = Icons.edit_note;
        break;
      case 'selection':
        label = 'Selecciona la palabra correcta';
        icon = Icons.touch_app;
        break;
      case 'scramble':
        label = 'Ordena las palabras';
        icon = Icons.shuffle;
        break;
      case 'type_in':
        label = 'Escribe la palabra que falta';
        icon = Icons.keyboard;
        break;
      case 'true_false':
        label = '¿Verdadero o falso?';
        icon = Icons.check_circle_outline;
        break;
      default:
        label = 'Ejercicio';
        icon = Icons.quiz;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue)),
      ],
    );
  }

  Widget _buildExerciseContent(String type, Map<String, dynamic> questionData, Map<String, dynamic> exercise) {
    switch (type) {
      case 'selection':
        return _buildSelectionExercise(questionData, exercise);
      case 'cloze':
      case 'type_in':
        return _buildTypeInExercise(questionData, exercise);
      case 'scramble':
        return _buildScrambleExercise(questionData, exercise);
      case 'true_false':
        return _buildTrueFalseExercise(questionData, exercise);
      default:
        return const Text('Tipo de ejercicio no soportado.');
    }
  }

  Widget _buildSelectionExercise(Map<String, dynamic> questionData, Map<String, dynamic> exercise) {
    final text = questionData['text'] ?? '';
    final options = questionData['options'] as List? ?? [];
    final correct = exercise['answer_data']['correct'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        if (questionData['hint'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Pista: empieza con "${questionData['hint']}"', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic), textAlign: TextAlign.center),
          ),
        const SizedBox(height: 30),
        ...options.map((option) {
          Color btnColor;
          if (_answered) {
            if (option == correct) {
              btnColor = Colors.green;
            } else if (_selectedOption == option) {
              btnColor = Colors.red;
            } else {
              btnColor = Colors.grey;
            }
          } else {
            btnColor = _selectedOption == option ? Colors.blue.shade900 : Colors.blue;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _answered ? null : () => _checkAnswer(option),
              child: Text(option.toString(), style: const TextStyle(fontSize: 16, color: Colors.white)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildScrambleExercise(Map<String, dynamic> questionData, Map<String, dynamic> exercise) {
    final template = List<String>.from(questionData['template'] ?? []);
    final words = List<String>.from(questionData['words'] ?? []);
    
    // Retrocompatibilidad: si no hay template, creamos uno básico
    if (template.isEmpty) {
      template.addAll(List.filled(words.length, '[BLANK]'));
    }

    int blanksCount = template.where((e) => e == '[BLANK]').length;
    
    List<String?> selected;
    if (_selectedOption is List) {
      selected = List<String?>.from(_selectedOption);
      if (selected.length != blanksCount) {
        selected = List<String?>.filled(blanksCount, null);
      }
    } else {
      selected = List<String?>.filled(blanksCount, null);
    }
    
    List<String> availableWords = List.from(words);
    for (var s in selected) {
      if (s != null) {
        availableWords.remove(s);
      }
    }

    int currentBlankIndex = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Texto con espacios
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue.shade200),
            borderRadius: BorderRadius.circular(12),
            color: Colors.blue.shade50,
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: template.map((item) {
              if (item == '[BLANK]') {
                int blankIdx = currentBlankIndex++;
                String? placedWord = selected[blankIdx];
                
                return DragTarget<Map<String, dynamic>>(
                  onAcceptWithDetails: _answered ? null : (details) {
                    setState(() {
                      final data = details.data;
                      final String draggedWord = data['word'];
                      final int sourceIndex = data['sourceIndex'];
                      
                      final newList = List<String?>.from(selected);
                      if (sourceIndex != -1) {
                        newList[sourceIndex] = null;
                      }
                      newList[blankIdx] = draggedWord;
                      _selectedOption = newList;
                    });
                  },
                  builder: (context, candidateData, rejectedData) {
                    bool isHovered = candidateData.isNotEmpty;
                    
                    if (placedWord != null) {
                      return Draggable<Map<String, dynamic>>(
                        data: {'word': placedWord, 'sourceIndex': blankIdx},
                        feedback: Material(color: Colors.transparent, child: Chip(label: Text(placedWord), elevation: 4)),
                        childWhenDragging: Opacity(opacity: 0.3, child: Chip(label: Text(placedWord))),
                        child: GestureDetector(
                          onTap: _answered ? null : () {
                             setState(() {
                                final newList = List<String?>.from(selected);
                                newList[blankIdx] = null;
                                _selectedOption = newList;
                             });
                          },
                          child: Chip(
                            label: Text(placedWord),
                            backgroundColor: _answered 
                                ? (exercise['answer_data']['correct_order'][blankIdx] == placedWord ? Colors.green : Colors.red)
                                : Colors.blue.shade100,
                          ),
                        ),
                      );
                    } else {
                      return Container(
                        width: 50,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: isHovered ? Colors.blue : Colors.grey.shade400, width: 2)),
                          color: isHovered ? Colors.blue.withOpacity(0.2) : Colors.transparent,
                        ),
                      );
                    }
                  },
                );
              } else {
                return Text(item, style: const TextStyle(fontSize: 18));
              }
            }).toList(),
          ),
        ),
        const Divider(height: 30),
        // Banco de palabras
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availableWords.map((word) {
            return Draggable<Map<String, dynamic>>(
              data: {'word': word, 'sourceIndex': -1},
              feedback: Material(color: Colors.transparent, child: Chip(label: Text(word), elevation: 4)),
              childWhenDragging: Opacity(opacity: 0.3, child: Chip(label: Text(word))),
              child: ActionChip(
                label: Text(word),
                backgroundColor: Colors.white,
                shape: StadiumBorder(side: BorderSide(color: Colors.grey.shade300)),
                onPressed: _answered ? null : () {
                   // Si toca una carta, se va al primer espacio vacío automáticamente
                   int firstEmpty = selected.indexOf(null);
                   if (firstEmpty != -1) {
                      setState(() {
                         final newList = List<String?>.from(selected);
                         newList[firstEmpty] = word;
                         _selectedOption = newList;
                      });
                   }
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTypeInExercise(Map<String, dynamic> questionData, Map<String, dynamic> exercise) {
    final text = questionData['text'] ?? questionData['context'] ?? '';
    final wordLength = questionData['word_length'] ?? 0;
    final hint = questionData['hint'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        if (hint != null)
          Text('Pista: $hint', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic), textAlign: TextAlign.center),
        if (wordLength > 0 && hint == null)
          Text('($wordLength letras)', style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
           controller: _textController,
           enabled: !_answered,
           textAlign: TextAlign.center,
           style: const TextStyle(fontSize: 20),
           decoration: InputDecoration(
             border: const OutlineInputBorder(),
             hintText: 'Escribe la palabra...',
             suffixIcon: _answered
                 ? Icon(_isCorrect ? Icons.check_circle : Icons.cancel, color: _isCorrect ? Colors.green : Colors.red)
                 : null,
           ),
           onSubmitted: _answered ? null : (value) => _checkAnswer(value),
        ),
      ],
    );
  }

  Widget _buildTrueFalseExercise(Map<String, dynamic> questionData, Map<String, dynamic> exercise) {
    final statement = questionData['statement'] ?? '';
    final instruction = questionData['instruction'] ?? '¿Es correcta esta afirmación?';
    final correct = exercise['answer_data']['correct'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(instruction, style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(statement, style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text('Verdadero', style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _answered
                      ? (correct == true ? Colors.green : (_selectedOption == true ? Colors.red : Colors.grey))
                      : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _answered ? null : () => _checkAnswer(true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text('Falso', style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _answered
                      ? (correct == false ? Colors.green : (_selectedOption == false ? Colors.red : Colors.grey))
                      : Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _answered ? null : () => _checkAnswer(false),
              ),
            ),
          ],
        ),
        if (_answered && exercise['answer_data']['explanation'] != null) ...[
          const SizedBox(height: 16),
          Text(
            exercise['answer_data']['explanation'],
            style: TextStyle(color: _isCorrect ? Colors.green.shade700 : Colors.red.shade700, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
