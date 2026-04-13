package br.com.postlymail;

import javafx.application.Application;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Stage;
import br.com.postlymail.util.HibernateUtil;

import java.io.IOException;

public class App extends Application {

    @Override
    public void start(Stage stage) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/br/com/postlymail/view/MainView.fxml"));
            Parent root = loader.load();
            
            Scene scene = new Scene(root, 1080, 720);
            scene.getStylesheets().add(getClass().getResource("/br/com/postlymail/css/style.css").toExternalForm());
            
            stage.setTitle("PostlyMail CRM - Premium");
            stage.setScene(scene);
            stage.show();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void stop() {
        HibernateUtil.shutdown();
    }

    public static void main(String[] args) {
        launch();
    }
}
