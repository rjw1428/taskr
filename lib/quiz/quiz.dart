import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/quiz/quiz.state.dart';
import 'package:taskr/services/firestore.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

class QuizScreen extends StatelessWidget {
  const QuizScreen({super.key, required this.quizId});
  final String quizId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
        create: (_) => QuizState(),
        child: FutureBuilder<Quiz>(
          future: FireStoreService().getQuiz(quizId),
          builder: (context, snapshot) {
            var state = Provider.of<QuizState>(context);

            if (!snapshot.hasData || snapshot.hasError) {
              return LoadingScreen();
            } else {
              var quiz = snapshot.data!;

              return Scaffold(
                appBar: AppBar(
                    title: AnimatedProgressbar(value: state.progress),
                    leading: IconButton(
                      icon: const Icon(FontAwesomeIcons.times),
                      onPressed: () => Navigator.pop(context),
                    )),
                body: PageView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  controller: state.controller,
                  onPageChanged: (int indx) =>
                      state.progress = (indx / quiz.questions.length + 1),
                  itemBuilder: (BuildContext context, int idx) {
                    if (idx == 0) {
                      return StartPage(quiz: quiz);
                    } else if (idx == quiz.questions.length + 1) {
                      return CongratsPage(quiz: quiz);
                    } else {
                      return QuestionPage(question: quiz.questions[idx - 1]);
                    }
                  },
                ),
              );
            }
          },
        ));
  }
}

class StartPage extends StatelessWidget {
  final Quiz quiz;
  const StartPage({Key? key, required this.quiz}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var state = Provider.of<QuizState>(context);

    return Container(
      padding: const EdgeInsets.all(20),
      child:
          Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(quiz.title, style: Theme.of(context).textTheme.headlineMedium),
        const Divider(),
        Expanded(child: Text(quiz.description)),
        ButtonBar(
          alignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton.icon(
                onPressed: state.nextPage,
                label: const Text('Start Quiz!'),
                icon: const Icon(Icons.poll)),
          ],
        )
      ]),
    );
  }
}

class CongratsPage extends StatelessWidget {
  final Quiz quiz;
  const CongratsPage({Key? key, required this.quiz}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    var state = Provider.of<QuizState>(context);

    return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Congrats! You completed the ${quiz.title} quiz.',
                textAlign: TextAlign.center),
            const Divider(),
            Image.asset('assets/congrats.gif'),
            const Divider(),
            ElevatedButton.icon(
              style: TextButton.styleFrom(backgroundColor: Colors.green),
              icon: const Icon(FontAwesomeIcons.check),
              label: const Text(' Mark Complete!'),
              onPressed: () {
                FireStoreService().updateReport(quiz);
                Navigator.pushNamedAndRemoveUntil(
                    context, '/topics', (route) => false);
                state.progress = 0;
              },
            )
          ],
        ));
  }
}

class QuestionPage extends StatelessWidget {
  final Question question;
  const QuestionPage({Key? key, required this.question}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var state = Provider.of<QuizState>(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
            child: Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.center,
                child: Text(question.text))),
        Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: question.options.map(
                (opt) {
                  return Container(
                      height: 90,
                      margin: const EdgeInsets.only(bottom: 10),
                      color: Colors.black26,
                      child: InkWell(
                          onTap: () {
                            state.selected = opt;
                            _bottomSheet(context, opt, state);
                          },
                          child: Container(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                Icon(
                                    state.selected == opt
                                        ? FontAwesomeIcons.checkCircle
                                        : FontAwesomeIcons.circle,
                                    size: 30),
                                Expanded(
                                    child: Container(
                                  margin: const EdgeInsets.only(left: 16),
                                  child: Text(opt.value,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ))
                              ]))));
                },
              ).toList(),
            ))
      ],
    );
  }
}

_bottomSheet(BuildContext context, Option opt, QuizState state) {
  bool correct = opt.correct;

  showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(correct ? 'Good Job!' : 'Wrong'),
                Text(
                  opt.detail,
                  style: const TextStyle(fontSize: 18, color: Colors.white54),
                ),
                ElevatedButton(
                    onPressed: () {
                      if (correct) {
                        state.nextPage();
                      }
                      Navigator.pop(context);
                    },
                    child: Text(correct ? 'Next Question' : 'Try Again',
                        style: const TextStyle(
                            color: Colors.white,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold)))
              ]),
        );
      });
}