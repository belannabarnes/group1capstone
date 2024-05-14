import React from 'react';
import axios from 'axios';

export default class PersonList extends React.Component {
  state = {
    persons: [
      {
        name: "Allison",
        id: 1,
      },
      {
        name: "Alex",
        id: 2,
      },
      {
        name: "Albert",
        id: 3,
      },
      {
        name: "B'Elanna",
        id: 4,
      }
    ]
  }

  componentDidMount() {
    axios.get(`https://84ipea4k3f.execute-api.us-west-2.amazonaws.com/prodgroup1/get-todo`)
      .then(res => {
        const persons = res.data.body;
        this.setState({ persons });
      })
  }

  render() {
    return (
      <ul>
        {
          this.state.persons
            .map(person =>
              <li key={person.id}>{person.id}{person.name}</li>
            )
        }
      </ul>
    )
  }
}
