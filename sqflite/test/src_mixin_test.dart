import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqlite_api.dart';

import 'package:sqflite/src/constant.dart';
import 'package:sqflite/src/database.dart';
import 'package:sqflite/src/mixin.dart';
import 'package:sqflite/src/open_options.dart';
import 'package:sqflite/utils/utils.dart';

void main() {
  group('mixin_flutter', () {
    run();
  });
}

class MockDatabase extends SqfliteDatabaseBase {
  MockDatabase(SqfliteDatabaseOpenHelper openHelper, [String name])
      : super(openHelper, name);

  int version;
  List<String> methods = <String>[];
  List<String> sqls = <String>[];
  List<Map<String, dynamic>> argumentsLists = <Map<String, dynamic>>[];

  @override
  Future<T> invokeMethod<T>(String method, [dynamic arguments]) async {
    // return super.invokeMethod(method, arguments);

    methods.add(method);
    if (arguments is Map) {
      argumentsLists.add(arguments.cast<String, dynamic>());
      if (arguments[paramOperations] != null) {
        final operations =
            arguments[paramOperations] as List<Map<String, dynamic>>;
        for (var operation in operations) {
          final sql = operation[paramSql] as String;
          sqls.add(sql);
        }
      } else {
        final sql = arguments[paramSql] as String;
        sqls.add(sql);

        // Basic version handling
        if (sql?.startsWith('PRAGMA user_version = ') == true) {
          version = int.tryParse(sql.split(' ').last);
        } else if (sql == 'PRAGMA user_version') {
          return <Map<String, dynamic>>[
            <String, dynamic>{'user_version': version}
          ] as T;
        }
      }
    } else {
      argumentsLists.add(null);
      sqls.add(null);
    }
    //devPrint('$method $arguments');
    return null;
  }
}

class MockDatabaseFactory extends SqfliteDatabaseFactoryBase {
  final List<String> methods = <String>[];
  final List<dynamic> argumentsList = <dynamic>[];
  final Map<String, MockDatabase> databases = <String, MockDatabase>{};

  @override
  Future<T> invokeMethod<T>(String method, [dynamic arguments]) {
    methods.add(method);
    argumentsList.add(arguments);
    return null;
  }

  SqfliteDatabase newEmptyDatabase() {
    final helper = SqfliteDatabaseOpenHelper(this, null, OpenDatabaseOptions());
    final db = helper.newDatabase(null);
    return db;
  }

  @override
  SqfliteDatabase newDatabase(
      SqfliteDatabaseOpenHelper openHelper, String path) {
    if (path != null) {
      final existing = databases[path];
      final db = MockDatabase(openHelper, path);
      // Copy version
      db.version = existing?.version;
      // Last replaces
      databases[path] = db;

      return db;
    }
    return MockDatabase(openHelper, path);
  }

  @override
  Future<String> getDatabasesPath() async {
    return join('.dart_tool', 'sqlite', 'test', 'mock');
  }
}

class MockDatabaseFactoryEmpty extends SqfliteDatabaseFactoryBase {
  final List<String> methods = <String>[];

  @override
  Future<T> invokeMethod<T>(String method, [dynamic arguments]) {
    methods.add(method);
    return null;
  }
}

/// This unfortunately won't work, you must extends SqfliteDatabaseFactory
class MockInvalidFactory implements DatabaseFactory {
  @override
  Future<bool> databaseExists(String path) async {
    return null;
  }

  @override
  Future<void> deleteDatabase(String path) async {}

  @override
  Future<String> getDatabasesPath() async {
    return null;
  }

  @override
  Future<Database> openDatabase(String path,
      {OpenDatabaseOptions options}) async {
    return null;
  }
}

final MockDatabaseFactory mockDatabaseFactory = MockDatabaseFactory();

void run() {
  group('database_factory', () {
    test('getDatabasesPath', () async {
      final factory = MockDatabaseFactoryEmpty();
      try {
        await factory.getDatabasesPath();
        fail('should fail');
      } on DatabaseException catch (_) {}
      expect(factory.methods, <String>['getDatabasesPath']);
      //expect(directory, )
    });
  });
  group('database', () {
    test('transaction', () async {
      final Database db = mockDatabaseFactory.newEmptyDatabase();
      await db.execute('test');
      await db.insert('test', <String, dynamic>{'test': 1});
      await db.update('test', <String, dynamic>{'test': 1});
      await db.delete('test');
      await db.query('test');

      await db.transaction((Transaction txn) async {
        await txn.execute('test');
        await txn.insert('test', <String, dynamic>{'test': 1});
        await txn.update('test', <String, dynamic>{'test': 1});
        await txn.delete('test');
        await txn.query('test');
      });

      final batch = db.batch();
      batch.execute('test');
      batch.insert('test', <String, dynamic>{'test': 1});
      batch.update('test', <String, dynamic>{'test': 1});
      batch.delete('test');
      batch.query('test');
      await batch.commit();
    });

    group('open', () {
      test('read-only', () async {
        // var db = mockDatabaseFactory.newEmptyDatabase();
        final db = await mockDatabaseFactory.openDatabase('test',
                options: SqfliteOpenDatabaseOptions(readOnly: true))
            as MockDatabase;
        await db.close();
        expect(db.methods, <String>['openDatabase', 'closeDatabase']);
        expect(db.argumentsLists.first, <String, dynamic>{
          'path': absolute(
              join(await mockDatabaseFactory.getDatabasesPath(), 'test')),
          'readOnly': true,
          'singleInstance': true
        });
      });
      test('not single_instance', () async {
        // var db = mockDatabaseFactory.newEmptyDatabase();
        final db = await mockDatabaseFactory.openDatabase('single_instance.db',
                options: SqfliteOpenDatabaseOptions(singleInstance: false))
            as MockDatabase;
        await db.close();
        expect(db.methods, <String>['openDatabase', 'closeDatabase']);
        expect(db.argumentsLists.first, <String, dynamic>{
          'path': absolute(join(await mockDatabaseFactory.getDatabasesPath(),
              'single_instance.db')),
          'singleInstance': false
        });
      });

      test('rollback transaction', () async {
        // var db = mockDatabaseFactory.newEmptyDatabase();
        final db = await mockDatabaseFactory.openDatabase(
                'rollback_transaction.db',
                options: SqfliteOpenDatabaseOptions(singleInstance: false))
            as MockDatabase;
        await db.execute('BEGIN TRANSACTION');
        await db.close();
        expect(db.methods,
            <String>['openDatabase', 'execute', 'execute', 'closeDatabase']);
        expect(db.argumentsLists.first, <String, dynamic>{
          'path': absolute(join(await mockDatabaseFactory.getDatabasesPath(),
              'rollback_transaction.db')),
          'singleInstance': false
        });
        expect(db.argumentsLists[2], <String, dynamic>{
          'sql': 'ROLLBACK',
          'arguments': null,
          'id': null,
          'inTransaction': false
        });
      });
      test('isOpen', () async {
        // var db = mockDatabaseFactory.newEmptyDatabase();
        final db = await mockDatabaseFactory.openDatabase('is_open.db',
                options: SqfliteOpenDatabaseOptions(readOnly: true))
            as MockDatabase;
        expect(db.isOpen, true);
        final closeFuture = db.close();
        // it is not closed right away
        expect(db.isOpen, true);
        await closeFuture;
        expect(db.isOpen, false);
      });

      test('reOpenSameVersion', () async {
        var db = await mockDatabaseFactory.openDatabase('on_reopen.db',
            options: OpenDatabaseOptions(
              version: 1,
            )) as MockDatabase;
        await db.close();

        expect(db.sqls, <String>[
          null,
          'BEGIN EXCLUSIVE',
          'PRAGMA user_version',
          'PRAGMA user_version = 1',
          'COMMIT',
          null
        ]);

        db = await mockDatabaseFactory.openDatabase('on_reopen.db',
            options: OpenDatabaseOptions(
              version: 1,
            )) as MockDatabase;
        await db.close();

        expect(db.sqls, <String>[
          null,
          'BEGIN EXCLUSIVE',
          'PRAGMA user_version',
          'COMMIT',
          null
        ]);
      });
    });
    group('openTransaction', () {
      test('onCreate', () async {
        final db = await mockDatabaseFactory.openDatabase('on_create.db',
            options: SqfliteOpenDatabaseOptions(
                version: 1,
                onCreate: (Database db, int version) async {
                  await db.execute('test1');
                  await db.transaction((Transaction txn) async {
                    await txn.execute('test2');
                  });
                })) as MockDatabase;

        await db.close();
        expect(db.methods, <String>[
          'openDatabase',
          'execute',
          'query',
          'execute',
          'execute',
          'execute',
          'execute',
          'closeDatabase'
        ]);
        expect(db.sqls, <String>[
          null,
          'BEGIN EXCLUSIVE',
          'PRAGMA user_version',
          'test1',
          'test2',
          'PRAGMA user_version = 1',
          'COMMIT',
          null
        ]);
      });

      test('onConfigure', () async {
        final db = await mockDatabaseFactory.openDatabase('on_configure.db',
            options: OpenDatabaseOptions(
                version: 1,
                onConfigure: (Database db) async {
                  await db.execute('test1');
                  await db.transaction((Transaction txn) async {
                    await txn.execute('test2');
                  });
                })) as MockDatabase;

        await db.close();
        expect(db.sqls, <String>[
          null,
          'test1',
          'BEGIN IMMEDIATE',
          'test2',
          'COMMIT',
          'BEGIN EXCLUSIVE',
          'PRAGMA user_version',
          'PRAGMA user_version = 1',
          'COMMIT',
          null
        ]);
      });

      test('onOpen', () async {
        final db = await mockDatabaseFactory.openDatabase('on_open',
            options: OpenDatabaseOptions(
                version: 1,
                onOpen: (Database db) async {
                  await db.execute('test1');
                  await db.transaction((Transaction txn) async {
                    await txn.execute('test2');
                  });
                })) as MockDatabase;

        await db.close();
        expect(db.sqls, <String>[
          null,
          'BEGIN EXCLUSIVE',
          'PRAGMA user_version',
          'PRAGMA user_version = 1',
          'COMMIT',
          'test1',
          'BEGIN IMMEDIATE',
          'test2',
          'COMMIT',
          null
        ]);
      });

      test('batch', () async {
        final db = await mockDatabaseFactory.openDatabase('test',
            options: OpenDatabaseOptions(
                version: 1,
                onConfigure: (Database db) async {
                  final batch = db.batch();
                  batch.execute('test1');
                  await batch.commit();
                },
                onCreate: (Database db, _) async {
                  final batch = db.batch();
                  batch.execute('test2');
                  await batch.commit(noResult: true);
                },
                onOpen: (Database db) async {
                  final batch = db.batch();
                  batch.execute('test3');
                  await batch.commit(continueOnError: true);
                })) as MockDatabase;

        await db.close();
        expect(db.sqls, <String>[
          null,
          'BEGIN IMMEDIATE',
          'test1',
          'COMMIT',
          'BEGIN EXCLUSIVE',
          'PRAGMA user_version',
          'test2',
          'PRAGMA user_version = 1',
          'COMMIT',
          'BEGIN IMMEDIATE',
          'test3',
          'COMMIT',
          null
        ]);
        expect(db.argumentsLists, <dynamic>[
          <String, dynamic>{
            'path': absolute(
                join(await mockDatabaseFactory.getDatabasesPath(), 'test')),
            'singleInstance': true
          },
          <String, dynamic>{
            'sql': 'BEGIN IMMEDIATE',
            'arguments': null,
            'id': null,
            'inTransaction': true
          },
          <String, dynamic>{
            'operations': <dynamic>[
              <String, dynamic>{
                'method': 'execute',
                'sql': 'test1',
                'arguments': null
              }
            ],
            'id': null
          },
          <String, dynamic>{
            'sql': 'COMMIT',
            'arguments': null,
            'id': null,
            'inTransaction': false
          },
          <String, dynamic>{
            'sql': 'BEGIN EXCLUSIVE',
            'arguments': null,
            'inTransaction': true,
            'id': null
          },
          <String, dynamic>{
            'sql': 'PRAGMA user_version',
            'arguments': null,
            'id': null
          },
          <String, dynamic>{
            'operations': <Map<String, dynamic>>[
              <String, dynamic>{
                'method': 'execute',
                'sql': 'test2',
                'arguments': null
              }
            ],
            'id': null,
            'noResult': true
          },
          <String, dynamic>{
            'sql': 'PRAGMA user_version = 1',
            'arguments': null,
            'id': null
          },
          <String, dynamic>{
            'sql': 'COMMIT',
            'arguments': null,
            'id': null,
            'inTransaction': false
          },
          <String, dynamic>{
            'sql': 'BEGIN IMMEDIATE',
            'arguments': null,
            'id': null,
            'inTransaction': true,
          },
          <String, dynamic>{
            'operations': <Map<String, dynamic>>[
              <String, dynamic>{
                'method': 'execute',
                'sql': 'test3',
                'arguments': null
              }
            ],
            'id': null,
            'continueOnError': true
          },
          <String, dynamic>{
            'sql': 'COMMIT',
            'arguments': null,
            'id': null,
            'inTransaction': false
          },
          <String, dynamic>{'id': null}
        ]);
      });
    });

    group('concurrency', () {
      test('concurrent 1', () async {
        final db = mockDatabaseFactory.newEmptyDatabase() as MockDatabase;
        final step1 = Completer<dynamic>();
        final step2 = Completer<dynamic>();
        final step3 = Completer<dynamic>();

        Future<void> action1() async {
          await db.execute('test');
          step1.complete();

          await step2.future;
          try {
            await db.execute('test').timeout(const Duration(milliseconds: 100));
            throw 'should fail';
          } catch (e) {
            expect(e is TimeoutException, true);
          }

          step3.complete();
        }

        Future<void> action2() async {
          // This is the change with concurrency 2
          await step1.future;
          await db.transaction((Transaction txn) async {
            // Wait for table being created;
            await txn.execute('test');
            step2.complete();

            await step3.future;

            await txn.execute('test');
          });
        }

        final Future<dynamic> future1 = action1();
        final Future<dynamic> future2 = action2();

        await Future.wait<dynamic>(<Future<dynamic>>[future1, future2]);
        // check ready
        await db.transaction<dynamic>((_) => null);
      });

      test('concurrent 2', () async {
        final db = mockDatabaseFactory.newEmptyDatabase() as MockDatabase;
        final step1 = Completer<dynamic>();
        final step2 = Completer<dynamic>();
        final step3 = Completer<dynamic>();

        Future<void> action1() async {
          await db.execute('test');
          step1.complete();

          await step2.future;
          try {
            await db.execute('test').timeout(const Duration(milliseconds: 100));
            throw 'should fail';
          } catch (e) {
            expect(e is TimeoutException, true);
          }

          step3.complete();
        }

        Future<void> action2() async {
          await db.transaction((Transaction txn) async {
            await step1.future;
            // Wait for table being created;
            await txn.execute('test');
            step2.complete();

            await step3.future;

            await txn.execute('test');
          });
        }

        final Future<dynamic> future1 = action1();
        final Future<dynamic> future2 = action2();

        await Future.wait<dynamic>(<Future<dynamic>>[future1, future2]);
      });
    });

    group('compatibility 1', () {
      test('concurrent 1', () async {
        final db = mockDatabaseFactory.newEmptyDatabase() as MockDatabase;
        final step1 = Completer<dynamic>();
        final step2 = Completer<dynamic>();
        final step3 = Completer<dynamic>();

        Future<void> action1() async {
          await db.execute('test');
          step1.complete();

          await step2.future;
          try {
            await db.execute('test').timeout(const Duration(milliseconds: 100));
            throw 'should fail';
          } catch (e) {
            expect(e is TimeoutException, true);
          }

          step3.complete();
        }

        Future<void> action2() async {
          // This is the change with concurrency 2
          await step1.future;
          await db.transaction((Transaction txn) async {
            // Wait for table being created;
            await txn.execute('test');
            step2.complete();

            await step3.future;

            await txn.execute('test');
          });
        }

        final Future<dynamic> future1 = action1();
        final Future<dynamic> future2 = action2();

        await Future.wait<dynamic>(<Future<dynamic>>[future1, future2]);
        // check ready
        await db.transaction<dynamic>((_) => null);
      });

      test('concurrent 2', () async {
        final db = mockDatabaseFactory.newEmptyDatabase() as MockDatabase;
        final step1 = Completer<dynamic>();
        final step2 = Completer<dynamic>();
        final step3 = Completer<dynamic>();

        Future<void> action1() async {
          await step1.future;
          try {
            await db.execute('test').timeout(const Duration(milliseconds: 100));
            throw 'should fail';
          } catch (e) {
            expect(e is TimeoutException, true);
          }

          await step2.future;
          try {
            await db.execute('test').timeout(const Duration(milliseconds: 100));
            throw 'should fail';
          } catch (e) {
            expect(e is TimeoutException, true);
          }

          step3.complete();
        }

        Future<void> action2() async {
          await db.transaction((Transaction txn) async {
            step1.complete();

            // Wait for table being created;
            await txn.execute('test');
            step2.complete();

            await step3.future;

            await txn.execute('test');
          });
        }

        final Future<dynamic> future2 = action2();
        final Future<dynamic> future1 = action1();

        await Future.wait<dynamic>(<Future<dynamic>>[future1, future2]);
        // check ready
        await db.transaction<dynamic>((_) => null);
      });
    });

    group('batch', () {
      test('simple', () async {
        final db = await mockDatabaseFactory.openDatabase('batch_simple.db')
            as MockDatabase;

        final batch = db.batch();
        batch.execute('test');
        await batch.commit();
        await batch.commit();
        await db.close();
        expect(db.methods, <String>[
          'openDatabase',
          'execute',
          'batch',
          'execute',
          'execute',
          'batch',
          'execute',
          'closeDatabase'
        ]);
        expect(db.sqls, <String>[
          null,
          'BEGIN IMMEDIATE',
          'test',
          'COMMIT',
          'BEGIN IMMEDIATE',
          'test',
          'COMMIT',
          null
        ]);
      });

      test('in_transaction', () async {
        final db = await mockDatabaseFactory
            .openDatabase('batch_in_transaction.db') as MockDatabase;

        await db.transaction((Transaction txn) async {
          final batch = txn.batch();
          batch.execute('test');

          await batch.commit();
          await batch.commit();
        });
        await db.close();
        expect(db.methods, <String>[
          'openDatabase',
          'execute',
          'batch',
          'batch',
          'execute',
          'closeDatabase'
        ]);
        expect(db.sqls,
            <String>[null, 'BEGIN IMMEDIATE', 'test', 'test', 'COMMIT', null]);
      });
    });

    group('instances', () {
      test('singleInstance same', () async {
        final futureDb1 = mockDatabaseFactory.openDatabase('test',
            options: OpenDatabaseOptions(singleInstance: true));
        final db2 = await mockDatabaseFactory.openDatabase('test',
            options: OpenDatabaseOptions(singleInstance: true)) as MockDatabase;
        final db1 = await futureDb1 as MockDatabase;
        expect(db1, db2);
      });
      test('singleInstance', () async {
        final futureDb1 = mockDatabaseFactory.openDatabase('test',
            options: OpenDatabaseOptions(singleInstance: true));
        final db2 = await mockDatabaseFactory.openDatabase('test',
            options: OpenDatabaseOptions(singleInstance: true)) as MockDatabase;
        final db1 = await futureDb1 as MockDatabase;
        final db3 = await mockDatabaseFactory.openDatabase('other',
            options: OpenDatabaseOptions(singleInstance: true)) as MockDatabase;
        final db4 = await mockDatabaseFactory.openDatabase(join('.', 'other'),
            options: OpenDatabaseOptions(singleInstance: true)) as MockDatabase;
        //expect(db1, db2);
        expect(db1, isNot(db3));
        expect(db3, db4);
        await db1.close();
        await db2.close();
        await db3.close();
      });

      test('multiInstances', () async {
        final futureDb1 = mockDatabaseFactory.openDatabase('multi_instances.db',
            options: OpenDatabaseOptions(singleInstance: false));
        final db2 = await mockDatabaseFactory.openDatabase('multi_instances.db',
                options: OpenDatabaseOptions(singleInstance: false))
            as MockDatabase;
        final db1 = await futureDb1 as MockDatabase;
        expect(db1, isNot(db2));
        await db1.close();
        await db2.close();
      });
    });

    test('dead lock', () async {
      final db = mockDatabaseFactory.newEmptyDatabase() as MockDatabase;
      var hasTimedOut = false;
      var callbackCount = 0;
      setLockWarningInfo(
          duration: const Duration(milliseconds: 200),
          callback: () {
            callbackCount++;
          });
      try {
        await db.transaction((Transaction txn) async {
          await db.execute('test');
          fail('should fail');
        }).timeout(const Duration(milliseconds: 500));
      } on TimeoutException catch (_) {
        hasTimedOut = true;
      }
      expect(hasTimedOut, isTrue);
      expect(callbackCount, 1);
      await db.close();
    });

    test('deleted/exists', () async {
      final path = 'test_exists.db';
      await mockDatabaseFactory.deleteDatabase(path);
      final exists = await mockDatabaseFactory.databaseExists(path);
      expect(exists, isNull);
      final expectedPath =
          absolute(join(await mockDatabaseFactory.getDatabasesPath(), path));
      expect(mockDatabaseFactory.methods,
          <String>['deleteDatabase', 'databaseExists']);
      expect(mockDatabaseFactory.argumentsList, <Map<String, dynamic>>[
        <String, dynamic>{'path': expectedPath},
        <String, dynamic>{'path': expectedPath}
      ]);
    });
  });
}
