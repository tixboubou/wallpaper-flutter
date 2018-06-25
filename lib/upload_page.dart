import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:wallpaper/models.dart';

class UploadPage extends StatefulWidget {
  @override
  _UploadPageState createState() => new _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  File _imageFile;
  List<ImageCategory> _imageCategories;
  ImageCategory _selectedCategory;
  StreamSubscription<List<ImageCategory>> subscription;
  TextEditingController _textController = new TextEditingController();

  final scaffoldKey = new GlobalKey<ScaffoldState>();
  final imagesCollection = Firestore.instance.collection('images');
  final categoriesCollection = Firestore.instance.collection('categories');
  final firebaseStorage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _imageCategories = <ImageCategory>[];
    subscription = categoriesCollection.snapshots().map((querySnapshot) {
      return querySnapshot.documents
          .map((doc) =>
              new ImageCategory.fromJson(id: doc.documentID, json: doc.data))
          .toList();
    }).listen((list) => setState(() => _imageCategories = list));
  }

  @override
  void dispose() {
    super.dispose();
    subscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      key: scaffoldKey,
      body: new Column(
        children: <Widget>[
          _buildImagePreview(),
          _buildCategoryDropDownButton(),
          _buildTextFieldName(),
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return new Flexible(
      child: new Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8),
        child: Material(
          borderRadius: BorderRadius.all(Radius.circular(6.0)),
          elevation: 3.0,
          child: _imageFile == null
              ? new Image.asset(
                  'assets/picture.png',
                  fit: BoxFit.cover,
                )
              : new Image.file(
                  _imageFile,
                  fit: BoxFit.cover,
                ),
        ),
      ),
      fit: FlexFit.tight,
    );
  }

  Widget _buildCategoryDropDownButton() {
    return new Padding(
      padding: const EdgeInsets.all(8.0),
      child: new Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _imageCategories.isEmpty
              ? Text("Loading categories...")
              : new DropdownButton<ImageCategory>(
                  items: _imageCategories.map((c) {
                    return new DropdownMenuItem<ImageCategory>(
                        child: new Text(c.name), value: c);
                  }).toList(),
                  onChanged: (c) => setState(() => _selectedCategory = c),
                  hint: Text('Select category'),
                  value: _selectedCategory,
                ),
          new IconButton(
            icon: Icon(Icons.add),
            onPressed: _showDialogAddCategory,
          ),
        ],
      ),
    );
  }

  Widget _buildTextFieldName() {
    return new TextField(
      controller: _textController,
      decoration: new InputDecoration(
        labelText: 'Image name',
        border: new OutlineInputBorder(),
        filled: true,
        contentPadding: const EdgeInsets.all(16.0),
      ),
      maxLines: 1,
    );
  }

  Widget _buildButtons() {
    return new Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        new Flexible(
          child: new FlatButton(
            padding: const EdgeInsets.all(16.0),
            onPressed: _chooseImage,
            child: Text(
              'Choose image',
              textAlign: TextAlign.center,
            ),
            color: Colors.black.withOpacity(0.7),
          ),
          fit: FlexFit.tight,
        ),
        new Flexible(
          child: new FlatButton(
            padding: const EdgeInsets.all(16.0),
            onPressed: _uploadImage,
            child: Text(
              'Upload',
              textAlign: TextAlign.center,
            ),
            color: Colors.black.withOpacity(0.7),
          ),
          fit: FlexFit.tight,
        ),
      ],
    );
  }

  _chooseImage() async {
    _imageFile = await ImagePicker.pickImage(source: ImageSource.gallery);
    _textController.text = path.basename(_imageFile.path);
    setState(() {});
  }

  _showSnackBar(String text,
      {Duration duration = const Duration(seconds: 1, milliseconds: 500)}) {
    return scaffoldKey.currentState.showSnackBar(
        new SnackBar(content: new Text(text), duration: duration));
  }

  bool _validate() {
    if (_imageFile == null) {
      _showSnackBar('Please select image');
      return false;
    }
    if (_selectedCategory == null) {
      _showSnackBar("Please select category");
      return false;
    }
    if (_textController.text.isEmpty) {
      _showSnackBar('Please provider name');
      return false;
    }
    return true;
  }

  _uploadImage() async {
    if (!_validate()) {
      return;
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return new Dialog(
            child: new Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                new CircularProgressIndicator(),
                new Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: new Text('Uploading...'),
                ),
              ],
            ),
          );
        });

    try {
      //upload file
      final extension = path.extension(_imageFile.path);
      final uploadPath = 'uploadImages/${new Uuid().v1()}${
          extension.isEmpty
              ? '.png'
              : extension
      }';
      final task1 =
          firebaseStorage.ref().child(uploadPath).putFile(_imageFile).future;

      final uploadThumbnail = (thumbnailBytes) {
        return firebaseStorage
            .ref()
            .child('uploadImages/${new Uuid().v1()}.png')
            .putData(thumbnailBytes)
            .future;
      };
      final task2 = compute<String, List<int>>(
        resizeImage,
        _imageFile.path,
      ).then(uploadThumbnail);

      final urls = await Future.wait([task1, task2]).then(
          (tasks) => tasks.map((task) => task.downloadUrl.toString()).toList());
      debugPrint("Urls: $urls");

      await imagesCollection.add(<String, dynamic>{
        'name': _textController.text,
        'imageUrl': urls[0],
        'thumbnailUrl': urls[1],
        'categoryId': _selectedCategory.id,
        'uploadedTime': DateTime.now(),
        'viewCount': 0,
        'downloadCount': 0,
      });

      Navigator.pop(context); //pop
      _showSnackBar('Image uploaded successfully');
    } on PlatformException catch (e) {
      Navigator.pop(context); //pop
      _showSnackBar(e.message);
    } catch (e) {
      Navigator.pop(context); //pop
      _showSnackBar("An error occurred");
      debugPrint('Error $e}');
    }
  }

  _showDialogAddCategory() {
    scaffoldKey.currentState.showBottomSheet((BuildContext context) {
      return new AddCategory();
    });
  }
}

List<int> resizeImage(String path) {
  final imageFile = new File(path);
  final src = img.decodeImage(imageFile.readAsBytesSync());
  final thumbnail = img.copyResize(src, 360, 640);
  return img.encodePng(thumbnail);
}

class AddCategory extends StatefulWidget {
  @override
  _AddCategoryState createState() => new _AddCategoryState();
}

class _AddCategoryState extends State<AddCategory> {
  final _textController = new TextEditingController();
  final categoriesCollection = Firestore.instance.collection('categories');
  final firebaseStorage = FirebaseStorage.instance;

  String _msg;
  File _imageFile;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return new Container(
      decoration: new BoxDecoration(
        borderRadius: new BorderRadius.only(
          topLeft: Radius.circular(8.0),
          topRight: Radius.circular(8.0),
        ),
      ),
      child: new Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          new Padding(
            padding: const EdgeInsets.all(8.0),
            child: new Text('Add new category'),
          ),
          new Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildTextField(),
          ),
          new Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildImagePreview(),
          ),
          new Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildProgressOrMsgTextOrButtonChooseImage(),
          ),
          new Padding(
            padding: const EdgeInsets.all(8.0),
            child: new Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                new FlatButton(
                  child: new Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                new FlatButton(
                  child: new Text('Add'),
                  onPressed: _addCategory,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressOrMsgTextOrButtonChooseImage() {
    return _isLoading
        ? new CircularProgressIndicator()
        : _msg != null
            ? Text(_msg)
            : new FlatButton.icon(
                onPressed: _chooseImage,
                icon: Icon(Icons.image),
                label: Text('Choose image'),
                color: Theme.of(context).primaryColorLight,
              );
  }

  Widget _buildImagePreview() {
    return _imageFile != null
        ? new Image.file(
            _imageFile,
            width: 36.0,
            height: 64.0,
            fit: BoxFit.cover,
          )
        : new Container();
  }

  TextField _buildTextField() {
    return new TextField(
      controller: _textController,
      decoration: new InputDecoration(
        labelText: 'Category name',
      ),
      maxLines: 1,
    );
  }

  _addCategory() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    //upload file
    final extension = path.extension(_imageFile.path);
    final uploadPath = 'uploadImages/${new Uuid().v1()}${
        extension.isEmpty
            ? '.png'
            : extension
    }';

    final task = await firebaseStorage
        .ref()
        .child(uploadPath)
        .putFile(_imageFile)
        .future;

    await categoriesCollection.add(<String, String>{
      'name': _textController.text,
      'imageUrl': task.downloadUrl.toString(),
    });

    if (!mounted) return;
    await _showMessage('New category added successfully');
    Navigator.pop(context);
  }

  bool _validate() {
    if (_imageFile == null) {
      _showMessage('Please select image');
      return false;
    }
    if (_textController.text.isEmpty) {
      _showMessage('Please provider name');
      return false;
    }
    return true;
  }

  _chooseImage() async {
    _imageFile = await ImagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 480.0,
      maxHeight: 854.0,
    );
    setState(() {});
  }

  _showMessage(String text,
      {Duration duration =
          const Duration(seconds: 1, milliseconds: 500)}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _msg = text;
    });
    await new Future.delayed(duration, () {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _msg = null;
      });
    });
  }
}